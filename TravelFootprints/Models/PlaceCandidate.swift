import Foundation
import CoreLocation

/// 一个可被查看、打卡的地点的值类型描述。
///
/// 来源可以是 MapKit 搜索结果（`init?(mapItem:)`，见 `MapItemAdapter.swift`），
/// 也可以是已保存的 `Place`。景点详情页统一使用该类型，
/// 打卡时再由 `CheckInStore` 匹配或创建对应的 `Place`。
struct PlaceCandidate: Identifiable, Hashable, Sendable {
    var name: String
    var address: String?
    var locality: String?
    var administrativeArea: String?
    var country: String?
    var countryCode: String?
    var latitude: Double
    var longitude: Double
    var mapItemIdentifier: String?
    var pointOfInterestCategory: String?
    var timeZoneIdentifier: String?

    var id: String {
        if let mapItemIdentifier { return mapItemIdentifier }
        let lat = (latitude * 100_000).rounded() / 100_000
        let lon = (longitude * 100_000).rounded() / 100_000
        return "\(name)|\(lat)|\(lon)"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    var cityCountryText: String? {
        LocationText.cityCountry(locality: locality, administrativeArea: administrativeArea, country: country)
    }

    var coordinateText: String {
        CoordinateFormatting.text(latitude: latitude, longitude: longitude)
    }

    /// 去除重复的搜索结果（保持原有顺序）。
    static func deduplicated(_ candidates: [PlaceCandidate]) -> [PlaceCandidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
    }
}

extension PlaceCandidate {
    init(place: Place) {
        self.init(
            name: place.name,
            address: place.address,
            locality: place.locality,
            administrativeArea: place.administrativeArea,
            country: place.country,
            countryCode: place.countryCode,
            latitude: place.latitude,
            longitude: place.longitude,
            mapItemIdentifier: place.mapItemIdentifier,
            pointOfInterestCategory: place.pointOfInterestCategory,
            timeZoneIdentifier: place.timeZoneIdentifier
        )
    }
}
