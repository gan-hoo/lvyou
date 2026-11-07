import Foundation
import MapKit
import Contacts

/// MKMapItem → PlaceCandidate 的唯一转换入口。
///
/// 注：iOS 26 SDK 中 `MKMapItem.placemark` 已被标记为将来弃用（以 `address` /
/// `addressRepresentations` 替代）。由于最低支持 iOS 17，这里继续使用 placemark，
/// 不会产生弃用警告；未来提高最低版本时，只需修改本文件。
extension PlaceCandidate {
    init?(mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        let coordinate = placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }

        var identifier: String?
        if #available(iOS 18.0, *) {
            identifier = mapItem.identifier?.rawValue
        }

        self.init(
            name: mapItem.name?.nilIfBlank ?? placemark.name?.nilIfBlank ?? String(localized: "未命名地点"),
            address: Self.formattedAddress(from: placemark),
            locality: placemark.locality,
            administrativeArea: placemark.administrativeArea,
            country: placemark.country,
            countryCode: placemark.isoCountryCode,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            mapItemIdentifier: identifier,
            pointOfInterestCategory: mapItem.pointOfInterestCategory?.rawValue,
            timeZoneIdentifier: mapItem.timeZone?.identifier
        )
    }

    private static func formattedAddress(from placemark: MKPlacemark) -> String? {
        if let postalAddress = placemark.postalAddress {
            let lines = CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
                .components(separatedBy: .newlines)
                .compactMap(\.nilIfBlank)
            if !lines.isEmpty {
                return lines.joined(separator: ", ")
            }
        }
        let parts = [placemark.thoroughfare, placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0?.nilIfBlank }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// 景点类别的本地化名称。
    var categoryDisplayName: String? {
        guard let pointOfInterestCategory else { return nil }
        switch MKPointOfInterestCategory(rawValue: pointOfInterestCategory) {
        case .museum: return String(localized: "博物馆")
        case .park: return String(localized: "公园")
        case .nationalPark: return String(localized: "国家公园")
        case .beach: return String(localized: "海滩")
        case .amusementPark: return String(localized: "游乐园")
        case .aquarium: return String(localized: "水族馆")
        case .zoo: return String(localized: "动物园")
        case .theater: return String(localized: "剧院")
        case .movieTheater: return String(localized: "电影院")
        case .stadium: return String(localized: "体育场馆")
        case .library: return String(localized: "图书馆")
        case .university: return String(localized: "大学")
        case .school: return String(localized: "学校")
        case .airport: return String(localized: "机场")
        case .hotel: return String(localized: "酒店")
        case .restaurant: return String(localized: "餐厅")
        case .cafe: return String(localized: "咖啡馆")
        case .bakery: return String(localized: "面包店")
        case .marina: return String(localized: "码头")
        case .campground: return String(localized: "露营地")
        case .winery: return String(localized: "酒庄")
        case .brewery: return String(localized: "啤酒厂")
        case .nightlife: return String(localized: "夜生活")
        case .publicTransport: return String(localized: "公共交通")
        case .store: return String(localized: "商店")
        case .foodMarket: return String(localized: "市场")
        default: return nil
        }
    }
}
