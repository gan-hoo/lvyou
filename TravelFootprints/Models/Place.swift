import Foundation
import SwiftData
import CoreLocation

/// 景点（用户至少打卡过一次的地点）。
///
/// CloudKit 兼容性约束（为后续 iCloud 同步预留）：
/// - 所有属性均为可选或带默认值；
/// - 不使用 `@Attribute(.unique)`；
/// - 关系均为可选。
@Model
final class Place {
    /// 本地唯一标识。
    var id: UUID = UUID()
    var name: String = ""
    /// 单行格式化地址。
    var address: String?
    /// 城市。
    var locality: String?
    /// 省 / 州。
    var administrativeArea: String?
    /// 国家或地区名称（按搜索时的系统语言）。
    var country: String?
    /// ISO 3166-1 国家代码，用于跨语言的国家统计。
    var countryCode: String?
    var latitude: Double = 0
    var longitude: Double = 0
    /// MapKit 提供的地点标识（iOS 18+ 可用），用于识别同一景点。
    var mapItemIdentifier: String?
    /// `MKPointOfInterestCategory` 的原始值。
    var pointOfInterestCategory: String?
    /// 景点所在时区，用于手动补录时的默认时区。
    var timeZoneIdentifier: String?
    /// 该景点的打卡验证半径（米）。默认 200 米，大型景区可扩展。
    var checkInRadius: Double = 200
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \CheckIn.place)
    var checkIns: [CheckIn]? = []

    init(
        id: UUID = UUID(),
        name: String,
        address: String? = nil,
        locality: String? = nil,
        administrativeArea: String? = nil,
        country: String? = nil,
        countryCode: String? = nil,
        latitude: Double,
        longitude: Double,
        mapItemIdentifier: String? = nil,
        pointOfInterestCategory: String? = nil,
        timeZoneIdentifier: String? = nil,
        checkInRadius: Double = 200,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.locality = locality
        self.administrativeArea = administrativeArea
        self.country = country
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.mapItemIdentifier = mapItemIdentifier
        self.pointOfInterestCategory = pointOfInterestCategory
        self.timeZoneIdentifier = timeZoneIdentifier
        self.checkInRadius = checkInRadius
        self.createdAt = createdAt
    }
}

extension Place {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    /// 有效的打卡记录，按到访时间倒序。
    var visits: [CheckIn] {
        (checkIns ?? [])
            .filter { !$0.isDeleted }
            .sorted { $0.visitedAt > $1.visitedAt }
    }

    var visitCount: Int {
        (checkIns ?? []).filter { !$0.isDeleted }.count
    }

    var latestVisit: CheckIn? {
        (checkIns ?? [])
            .filter { !$0.isDeleted }
            .max { $0.visitedAt < $1.visitedAt }
    }

    /// 用于统计的城市名（仅使用 locality，避免把省 / 州算作城市）。
    var cityName: String? { locality?.nilIfBlank }

    /// 跨语言稳定的国家键：优先 ISO 代码。
    var countryKey: String? { countryCode?.nilIfBlank?.uppercased() ?? country?.nilIfBlank }

    /// 例如「悉尼 · 澳大利亚」。
    var cityCountryText: String? {
        LocationText.cityCountry(locality: locality, administrativeArea: administrativeArea, country: country)
    }
}
