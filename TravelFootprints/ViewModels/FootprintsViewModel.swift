import Foundation
import Observation

/// 足迹筛选条件（纯值类型，便于测试）。
struct FootprintFilter: Equatable {
    /// 国家显示名；nil 表示全部。
    var country: String?
    /// 城市名；nil 表示全部。
    var city: String?

    var isActive: Bool { country != nil || city != nil }

    func apply(to places: [Place]) -> [Place] {
        places.filter { place in
            if let country, place.country?.nilIfBlank != country { return false }
            if let city, place.cityName != city { return false }
            return true
        }
    }

    static func countries(in places: [Place]) -> [String] {
        Set(places.compactMap { $0.country?.nilIfBlank }).sortedLocalized()
    }

    static func cities(in places: [Place], country: String?) -> [String] {
        let scoped = country.map { country in places.filter { $0.country?.nilIfBlank == country } } ?? places
        return Set(scoped.compactMap(\.cityName)).sortedLocalized()
    }
}

/// 当前筛选下的足迹汇总。
struct FootprintSummary: Equatable {
    let checkInCount: Int
    let placeCount: Int
    let cityCount: Int

    init(places: [Place]) {
        checkInCount = places.reduce(0) { $0 + $1.visitCount }
        placeCount = places.count
        cityCount = Set(places.compactMap { place in
            place.cityName.map { "\(place.countryKey ?? "")|\($0.lowercased())" }
        }).count
    }
}

@MainActor
@Observable
final class FootprintsViewModel {
    var filter = FootprintFilter()
    var selectedPlaceID: UUID?

    /// 有打卡记录的景点。
    func visitedPlaces(from places: [Place]) -> [Place] {
        places.filter { $0.visitCount > 0 }
    }

    /// 筛选后按最近到访时间倒序排列。
    func visiblePlaces(from places: [Place]) -> [Place] {
        filter.apply(to: visitedPlaces(from: places)).sorted {
            ($0.latestVisit?.visitedAt ?? .distantPast) > ($1.latestVisit?.visitedAt ?? .distantPast)
        }
    }

    func countries(from places: [Place]) -> [String] {
        FootprintFilter.countries(in: visitedPlaces(from: places))
    }

    func cities(from places: [Place]) -> [String] {
        FootprintFilter.cities(in: visitedPlaces(from: places), country: filter.country)
    }

    func selectCountry(_ country: String?) {
        filter.country = country
        filter.city = nil
        selectedPlaceID = nil
    }

    func selectCity(_ city: String?) {
        filter.city = city
        selectedPlaceID = nil
    }

    func resetFilter() {
        filter = FootprintFilter()
        selectedPlaceID = nil
    }
}

private extension Set where Element == String {
    func sortedLocalized() -> [String] {
        sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
