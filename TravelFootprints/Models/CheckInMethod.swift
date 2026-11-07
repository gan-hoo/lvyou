import Foundation

/// 打卡方式。
///
/// 以原始字符串持久化（见 `CheckIn.methodRawValue`），
/// 便于 SwiftData 谓词查询、CloudKit 同步及数据导出。
enum CheckInMethod: String, Codable, CaseIterable, Sendable {
    /// 通过实时 GPS 坐标验证、位于景点打卡半径内的打卡。
    case gpsVerified = "gps"
    /// 用户手动补录的过去旅行，未经过位置验证。
    case manual = "manual"

    var displayName: String {
        switch self {
        case .gpsVerified: String(localized: "GPS 验证")
        case .manual: String(localized: "手动记录")
        }
    }

    var systemImage: String {
        switch self {
        case .gpsVerified: "checkmark.seal.fill"
        case .manual: "square.and.pencil"
        }
    }
}
