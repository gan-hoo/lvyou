import Foundation

/// 基于本地真实数据计算的旅行统计。
struct TravelStatistics {
    struct YearCount: Identifiable, Equatable {
        let year: Int
        let count: Int
        var id: Int { year }
    }

    let countryCount: Int
    let cityCount: Int
    let placeCount: Int
    let checkInCount: Int
    let latestCheckIn: CheckIn?
    /// 按年份倒序；年份以打卡地当地日期计算。
    let yearlyCounts: [YearCount]

    init(checkIns: [CheckIn]) {
        let valid = checkIns.filter { !$0.isDeleted }
        let places = valid.compactMap(\.place)

        var placeIDs = Set<UUID>()
        var countries = Set<String>()
        var cities = Set<String>()
        for place in places {
            placeIDs.insert(place.id)
            let country = place.countryKey
            if let country { countries.insert(country) }
            if let city = place.cityName {
                cities.insert("\(country ?? "")|\(city.lowercased())")
            }
        }

        var byYear: [Int: Int] = [:]
        for checkIn in valid {
            byYear[checkIn.localYear, default: 0] += 1
        }

        countryCount = countries.count
        cityCount = cities.count
        placeCount = placeIDs.count
        checkInCount = valid.count
        latestCheckIn = valid.max { $0.visitedAt < $1.visitedAt }
        yearlyCounts = byYear
            .map { YearCount(year: $0.key, count: $0.value) }
            .sorted { $0.year > $1.year }
    }
}
