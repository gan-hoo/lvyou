import Foundation
import CoreLocation
import Observation

/// 定位错误。所有失败都明确上报，绝不伪造定位成功。
enum LocationError: LocalizedError, Equatable {
    case denied
    case restricted
    case preciseLocationRequired
    case timeout
    case unavailable

    init(_ error: Error) {
        if let locationError = error as? LocationError {
            self = locationError
        } else if let clError = error as? CLError, clError.code == .denied {
            self = .denied
        } else {
            self = .unavailable
        }
    }

    var errorDescription: String? {
        switch self {
        case .denied: String(localized: "定位权限未开启")
        case .restricted: String(localized: "定位功能受限")
        case .preciseLocationRequired: String(localized: "需要精确位置")
        case .timeout: String(localized: "定位超时")
        case .unavailable: String(localized: "无法获取位置")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .denied:
            String(localized: "请在「设置」中允许旅行足迹在使用 App 期间访问你的位置，才能进行 GPS 验证打卡。")
        case .restricted:
            String(localized: "此设备的定位功能受到限制（例如屏幕使用时间或设备管理），无法进行 GPS 打卡。")
        case .preciseLocationRequired:
            String(localized: "GPS 打卡需要开启「精确位置」。请在「设置」中为旅行足迹打开精确位置。")
        case .timeout:
            String(localized: "暂时无法获取你的位置。请移动到开阔区域后重试。")
        case .unavailable:
            String(localized: "当前无法确定你的位置，请确认定位服务已开启后重试。")
        }
    }

    /// 用户可以通过系统设置解决的错误。
    var canBeFixedInSettings: Bool {
        self == .denied || self == .preciseLocationRequired
    }
}

/// 基于 Core Location 的按需单次定位服务。
///
/// 隐私设计：
/// - 仅在用户主动操作（GPS 打卡、查看距离、定位按钮）时请求权限；
/// - 只使用 `requestLocation()` 获取单次位置，不开启持续定位，也不保存移动轨迹；
/// - 不申请后台定位。
@MainActor
@Observable
final class LocationService: NSObject {
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    /// 最近一次成功获取的位置（仅保存在内存中）。
    private(set) var lastLocation: CLLocation?

    private let manager: CLLocationManager
    @ObservationIgnored private var authorizationWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    @ObservationIgnored private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    /// 对应 Info.plist 中 `NSLocationTemporaryUsageDescriptionDictionary` 的键。
    static let temporaryAccuracyPurposeKey = "CheckInVerification"

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .other
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// 若尚未询问过，则弹出系统授权框并等待用户选择。
    @discardableResult
    func requestAuthorizationIfNeeded() async -> CLAuthorizationStatus {
        let current = manager.authorizationStatus
        guard current == .notDetermined else {
            refreshAuthorizationState()
            return current
        }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// 获取一次当前位置。
    /// - Parameters:
    ///   - requiresFullAccuracy: GPS 打卡需要精确位置；若用户只授权了大致位置，会请求临时精确位置。
    ///   - timeout: 超时后抛出 `LocationError.timeout`。
    func requestCurrentLocation(
        requiresFullAccuracy: Bool = true,
        timeout: Duration = .seconds(15)
    ) async throws -> CLLocation {
        switch await requestAuthorizationIfNeeded() {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .restricted:
            throw LocationError.restricted
        case .denied, .notDetermined:
            throw LocationError.denied
        @unknown default:
            throw LocationError.unavailable
        }

        if requiresFullAccuracy, manager.accuracyAuthorization == .reducedAccuracy {
            try? await manager.requestTemporaryFullAccuracyAuthorization(
                withPurposeKey: Self.temporaryAccuracyPurposeKey
            )
            refreshAuthorizationState()
            guard manager.accuracyAuthorization == .fullAccuracy else {
                throw LocationError.preciseLocationRequired
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            enqueueLocationRequest(continuation, timeout: timeout)
        }
    }

    // MARK: - Private

    private func enqueueLocationRequest(_ continuation: CheckedContinuation<CLLocation, Error>, timeout: Duration) {
        locationWaiters.append(continuation)
        // 已有进行中的请求时合并等待，避免重复定位。
        guard locationWaiters.count == 1 else { return }
        manager.requestLocation()
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finishLocationRequest(with: .failure(LocationError.timeout))
        }
    }

    private func finishLocationRequest(with result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if case .success(let location) = result {
            lastLocation = location
        }
        let waiters = locationWaiters
        locationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }

    private func refreshAuthorizationState() {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }

    private func handleAuthorizationChange() {
        refreshAuthorizationState()
        guard authorizationStatus != .notDetermined else { return }
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: authorizationStatus)
        }
    }
}

// CLLocationManager 会在创建它的线程（主线程）上回调代理方法。
extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            self.handleAuthorizationChange()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            self.finishLocationRequest(with: .success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let mapped = LocationError(error)
        MainActor.assumeIsolated {
            self.finishLocationRequest(with: .failure(mapped))
        }
    }
}
