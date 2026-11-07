import Foundation
import SwiftData
import CoreLocation

/// 一次打卡记录。同一景点可以多次打卡，每次形成独立记录。
///
/// 时间存储策略：
/// - `visitedAt` 为绝对时间点（`Date` 本身与时区无关，等价于 UTC 时间戳）；
/// - `timeZoneIdentifier` 保存打卡时的 IANA 时区标识（如 `Asia/Tokyo`）；
/// - `utcOffsetSeconds` 保存打卡当时的 UTC 偏移，作为时区规则变化时的兜底。
/// 展示时始终使用记录自身的时区，因此跨国旅行不会出现日期错位。
@Model
final class CheckIn {
    var id: UUID = UUID()
    var place: Place?
    /// 记录写入数据库的时间。
    var createdAt: Date = Date()
    /// 实际到访时间。
    var visitedAt: Date = Date()
    var timeZoneIdentifier: String = "UTC"
    var utcOffsetSeconds: Int = 0
    /// `CheckInMethod` 原始值。默认值为 manual，确保任何异常数据都不会被误认为 GPS 验证。
    var methodRawValue: String = "manual"
    /// 打卡时设备的真实 GPS 坐标（仅 GPS 验证打卡）。
    var gpsLatitude: Double?
    var gpsLongitude: Double?
    /// GPS 水平精度（米）。
    var gpsHorizontalAccuracy: Double?
    /// 打卡时与景点坐标的距离（米）。
    var distanceFromPlace: Double?
    var note: String = ""
    /// 照片在 App 沙盒中的相对文件名（第二阶段启用）。
    var photoFileNames: [String] = []
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        visitedAt: Date,
        timeZone: TimeZone,
        method: CheckInMethod,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil,
        gpsHorizontalAccuracy: Double? = nil,
        distanceFromPlace: Double? = nil,
        note: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.visitedAt = visitedAt
        self.timeZoneIdentifier = timeZone.identifier
        self.utcOffsetSeconds = timeZone.secondsFromGMT(for: visitedAt)
        self.methodRawValue = method.rawValue
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.gpsHorizontalAccuracy = gpsHorizontalAccuracy
        self.distanceFromPlace = distanceFromPlace
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension CheckIn {
    var method: CheckInMethod {
        CheckInMethod(rawValue: methodRawValue) ?? .manual
    }

    var isGPSVerified: Bool { method == .gpsVerified }

    /// 打卡时的时区。
    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier)
            ?? TimeZone(secondsFromGMT: utcOffsetSeconds)
            ?? .gmt
    }

    var gpsCoordinate: CLLocationCoordinate2D? {
        guard let gpsLatitude, let gpsLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: gpsLatitude, longitude: gpsLongitude)
    }

    /// 打卡地当地时间，例如「2026年11月7日，16:30」。
    var localDateTimeText: String {
        CheckInDateFormatter.dateTimeText(for: visitedAt, timeZone: timeZone)
    }

    var timeZoneText: String {
        CheckInDateFormatter.timeZoneText(for: timeZone, at: visitedAt)
    }

    /// 打卡地当地日期所在年份。
    var localYear: Int {
        CheckInDateFormatter.localComponents(for: visitedAt, timeZone: timeZone).year ?? 0
    }
}
