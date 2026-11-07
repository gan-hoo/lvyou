import Foundation
import CoreLocation

/// 打卡验证的全局阈值。
enum CheckInPolicy {
    /// 默认打卡半径：200 米。
    static let defaultRadius: CLLocationDistance = 200
    /// 可接受的最大 GPS 水平误差。误差过大时不允许验证。
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 100
    /// 可接受的定位数据最大时长（秒），避免使用缓存的旧位置。
    static let maximumLocationAge: TimeInterval = 60
}

/// 打卡半径规则。
///
/// 当前所有景点统一使用 200 米。对于占地较大的景区（国家公园、大型主题乐园等），
/// 后续可以在 `categoryOverrides` 中按 `MKPointOfInterestCategory` 原始值配置更大的半径，
/// 或直接修改 `Place.checkInRadius`。
struct CheckInRadiusRule: Sendable {
    var defaultRadius: CLLocationDistance = CheckInPolicy.defaultRadius
    var categoryOverrides: [String: CLLocationDistance] = [:]

    static let standard = CheckInRadiusRule()

    func radius(forCategory category: String?) -> CLLocationDistance {
        guard let category, let override = categoryOverrides[category] else { return defaultRadius }
        return override
    }
}

/// 验证结果。
enum CheckInVerification: Equatable {
    case verified(distance: CLLocationDistance)
    case tooFar(distance: CLLocationDistance, radius: CLLocationDistance)
    case inaccurate(horizontalAccuracy: CLLocationAccuracy)
    case stale(age: TimeInterval)

    var isVerified: Bool {
        if case .verified = self { return true }
        return false
    }
}

/// 纯逻辑的 GPS 打卡验证器，不依赖任何系统状态，便于单元测试。
struct CheckInValidator {
    var maximumHorizontalAccuracy: CLLocationAccuracy = CheckInPolicy.maximumHorizontalAccuracy
    var maximumLocationAge: TimeInterval = CheckInPolicy.maximumLocationAge

    func evaluate(
        distance: CLLocationDistance,
        horizontalAccuracy: CLLocationAccuracy,
        locationAge: TimeInterval,
        radius: CLLocationDistance
    ) -> CheckInVerification {
        // 负数精度表示坐标无效。
        if horizontalAccuracy < 0 || horizontalAccuracy > maximumHorizontalAccuracy {
            return .inaccurate(horizontalAccuracy: horizontalAccuracy)
        }
        if locationAge > maximumLocationAge {
            return .stale(age: locationAge)
        }
        if distance.isFinite, distance <= radius {
            return .verified(distance: distance)
        }
        return .tooFar(distance: distance, radius: radius)
    }

    func validate(
        location: CLLocation,
        target: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        now: Date = .now
    ) -> CheckInVerification {
        let targetLocation = CLLocation(latitude: target.latitude, longitude: target.longitude)
        return evaluate(
            distance: location.distance(from: targetLocation),
            horizontalAccuracy: location.horizontalAccuracy,
            locationAge: now.timeIntervalSince(location.timestamp),
            radius: radius
        )
    }
}
