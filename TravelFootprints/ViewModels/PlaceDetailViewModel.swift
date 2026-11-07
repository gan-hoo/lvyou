import Foundation
import CoreLocation
import Observation

/// 打卡失败原因，均可直接展示给用户。
enum CheckInFailure: Error, Equatable {
    case location(LocationError)
    case tooFar(distance: CLLocationDistance, radius: CLLocationDistance)
    case inaccurate(horizontalAccuracy: CLLocationAccuracy)
    case staleLocation
    case storage(String)

    var title: String {
        switch self {
        case .location(let error): error.errorDescription ?? String(localized: "无法获取位置")
        case .tooFar: String(localized: "距离景点太远")
        case .inaccurate: String(localized: "定位精度不足")
        case .staleLocation: String(localized: "位置信息已过期")
        case .storage: String(localized: "保存失败")
        }
    }

    var message: String {
        switch self {
        case .location(let error):
            return error.recoverySuggestion ?? ""
        case .tooFar(let distance, let radius):
            let distanceText = DistanceFormatting.text(for: distance)
            let radiusText = DistanceFormatting.text(for: radius)
            return String(localized: "你距离景点约 \(distanceText)，需要在 \(radiusText) 范围内才能完成 GPS 打卡。")
        case .inaccurate(let accuracy):
            if accuracy < 0 {
                return String(localized: "当前定位信号无效。请稍候或移动到开阔区域后重试。")
            }
            let accuracyText = DistanceFormatting.text(for: accuracy)
            return String(localized: "当前定位误差约 ±\(accuracyText)，不足以验证打卡。请稍候或移动到开阔区域后重试。")
        case .staleLocation:
            return String(localized: "获取到的位置信息过旧，请重试。")
        case .storage(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .location: "location.slash"
        case .tooFar: "figure.walk"
        case .inaccurate, .staleLocation: "location.magnifyingglass"
        case .storage: "externaldrive.badge.exclamationmark"
        }
    }

    var canOpenSettings: Bool {
        if case .location(let error) = self { return error.canBeFixedInSettings }
        return false
    }

    var canRetry: Bool {
        if case .location(.restricted) = self { return false }
        return true
    }
}

@MainActor
@Observable
final class PlaceDetailViewModel {
    let candidate: PlaceCandidate

    /// 已保存的对应景点（尚未打卡过则为 nil）。
    private(set) var matchedPlace: Place?
    private(set) var isCheckingIn = false
    private(set) var isRefreshingDistance = false
    private(set) var currentDistance: CLLocationDistance?
    private(set) var currentAccuracy: CLLocationAccuracy?
    var failure: CheckInFailure?
    /// 刚刚完成的 GPS 打卡，用于展示成功页。
    var completedCheckIn: CheckIn?
    /// 触觉反馈触发器。
    private(set) var successCount = 0
    private(set) var failureCount = 0

    @ObservationIgnored private let validator: CheckInValidator
    @ObservationIgnored private let radiusRule: CheckInRadiusRule

    init(candidate: PlaceCandidate, validator: CheckInValidator = CheckInValidator(), radiusRule: CheckInRadiusRule = .standard) {
        self.candidate = candidate
        self.validator = validator
        self.radiusRule = radiusRule
    }

    var radius: CLLocationDistance {
        matchedPlace?.checkInRadius ?? radiusRule.radius(forCategory: candidate.pointOfInterestCategory)
    }

    var isWithinRange: Bool? {
        currentDistance.map { $0 <= radius }
    }

    var visits: [CheckIn] {
        matchedPlace?.visits ?? []
    }

    /// 手动补录默认时区：景点所在时区 → 设备当前时区。
    var defaultTimeZone: TimeZone {
        matchedPlace?.timeZone ?? candidate.timeZone ?? .current
    }

    func resolvePlace(using store: CheckInStore) {
        matchedPlace = try? store.existingPlace(matching: candidate)
    }

    func onAppear(store: CheckInStore, locationService: LocationService) async {
        resolvePlace(using: store)
        // 仅在已授权时静默刷新距离，不会在进入页面时弹出权限框。
        if locationService.isAuthorized, currentDistance == nil {
            await refreshDistance(using: locationService)
        }
    }

    /// 刷新与景点的距离。未授权时会请求权限（由用户点击触发）。
    func refreshDistance(using locationService: LocationService) async {
        guard !isRefreshingDistance else { return }
        isRefreshingDistance = true
        defer { isRefreshingDistance = false }
        do {
            let location = try await locationService.requestCurrentLocation(requiresFullAccuracy: false)
            currentDistance = location.distance(from: candidate.location)
            currentAccuracy = location.horizontalAccuracy
        } catch {
            // 距离仅用于参考，失败时保持未知，由界面展示权限状态。
        }
    }

    /// GPS 验证打卡。
    func performGPSCheckIn(store: CheckInStore, locationService: LocationService) async {
        guard !isCheckingIn else { return }
        isCheckingIn = true
        failure = nil
        defer { isCheckingIn = false }

        do {
            let location = try await locationService.requestCurrentLocation(requiresFullAccuracy: true)
            currentDistance = location.distance(from: candidate.location)
            currentAccuracy = location.horizontalAccuracy

            let radius = self.radius
            switch validator.validate(location: location, target: candidate.coordinate, radius: radius) {
            case .verified(let distance):
                let record = try store.recordGPSCheckIn(
                    for: candidate,
                    location: location,
                    distance: distance,
                    radius: radius
                )
                matchedPlace = record.place
                successCount += 1
                completedCheckIn = record
            case .tooFar(let distance, let radius):
                fail(.tooFar(distance: distance, radius: radius))
            case .inaccurate(let accuracy):
                fail(.inaccurate(horizontalAccuracy: accuracy))
            case .stale:
                fail(.staleLocation)
            }
        } catch let error as LocationError {
            fail(.location(error))
        } catch {
            fail(.storage(error.localizedDescription))
        }
    }

    /// 手动补录。
    func saveManualCheckIn(visitedAt: Date, timeZone: TimeZone, note: String, store: CheckInStore) throws {
        let record = try store.recordManualCheckIn(
            for: candidate,
            visitedAt: visitedAt,
            timeZone: timeZone,
            note: note
        )
        matchedPlace = record.place
        failure = nil
        successCount += 1
    }

    func dismissFailure() {
        failure = nil
    }

    private func fail(_ failure: CheckInFailure) {
        self.failure = failure
        failureCount += 1
    }
}
