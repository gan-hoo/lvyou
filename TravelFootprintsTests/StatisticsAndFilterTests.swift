import Testing
import Foundation
import SwiftData
@testable import TravelFootprints

@MainActor
struct StatisticsAndFilterTests {
    let container: ModelContainer
    let store: CheckInStore

    init() throws {
        container = TestFixtures.makeContainer()
        store = CheckInStore(context: container.mainContext)

        let sydney = try #require(TimeZone(identifier: "Australia/Sydney"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let paris = try #require(TimeZone(identifier: "Europe/Paris"))

        try store.recordManualCheckIn(for: TestFixtures.operaHouse, visitedAt: TestFixtures.date("2026-01-10T02:00:00Z"), timeZone: sydney)
        try store.recordManualCheckIn(for: TestFixtures.operaHouse, visitedAt: TestFixtures.date("2026-11-01T02:00:00Z"), timeZone: sydney)
        try store.recordManualCheckIn(for: TestFixtures.tokyoTower, visitedAt: TestFixtures.date("2025-05-01T03:00:00Z"), timeZone: tokyo)
        try store.recordManualCheckIn(for: TestFixtures.sensoji, visitedAt: TestFixtures.date("2025-05-02T03:00:00Z"), timeZone: tokyo)
        // UTC 为 2024 年，巴黎当地时间为 2025 年元旦。
        try store.recordManualCheckIn(for: TestFixtures.eiffelTower, visitedAt: TestFixtures.date("2024-12-31T23:30:00Z"), timeZone: paris)
    }

    private func allCheckIns() throws -> [CheckIn] {
        try container.mainContext.fetch(FetchDescriptor<CheckIn>())
    }

    private func allPlaces() throws -> [Place] {
        try container.mainContext.fetch(FetchDescriptor<Place>())
    }

    @Test func statisticsComeFromStoredData() throws {
        let stats = TravelStatistics(checkIns: try allCheckIns())

        #expect(stats.countryCount == 3)
        #expect(stats.cityCount == 3)
        #expect(stats.placeCount == 4)
        #expect(stats.checkInCount == 5)
        #expect(stats.latestCheckIn?.visitedAt == TestFixtures.date("2026-11-01T02:00:00Z"))
        #expect(stats.yearlyCounts == [
            .init(year: 2026, count: 2),
            .init(year: 2025, count: 3)
        ])
    }

    @Test func emptyStatistics() {
        let stats = TravelStatistics(checkIns: [])
        #expect(stats.countryCount == 0)
        #expect(stats.checkInCount == 0)
        #expect(stats.latestCheckIn == nil)
        #expect(stats.yearlyCounts.isEmpty)
    }

    @Test func filterByCountryAndCity() throws {
        let places = try allPlaces()

        #expect(FootprintFilter.countries(in: places).count == 3)
        #expect(FootprintFilter.cities(in: places, country: "日本") == ["东京"])

        let japan = FootprintFilter(country: "日本").apply(to: places)
        #expect(Set(japan.map(\.name)) == ["东京塔", "浅草寺"])

        let sydney = FootprintFilter(country: "澳大利亚", city: "Sydney").apply(to: places)
        #expect(sydney.map(\.name) == ["Sydney Opera House"])

        #expect(FootprintFilter().apply(to: places).count == 4)
    }

    @Test func footprintSummaryCountsVisits() throws {
        let summary = FootprintSummary(places: try allPlaces())
        #expect(summary.checkInCount == 5)
        #expect(summary.placeCount == 4)
        #expect(summary.cityCount == 3)
    }

    @Test func viewModelSortsByMostRecentVisit() throws {
        let viewModel = FootprintsViewModel()
        let visible = viewModel.visiblePlaces(from: try allPlaces())
        #expect(visible.first?.name == "Sydney Opera House")

        viewModel.selectCountry("日本")
        #expect(viewModel.visiblePlaces(from: try allPlaces()).map(\.name) == ["浅草寺", "东京塔"])
    }

    @Test func timelineGroupsByLocalMonth() throws {
        let sections = TimelineSection.make(from: try allCheckIns(), locale: Locale(identifier: "zh_Hans_CN"))
        #expect(sections.map(\.id) == [202611, 202601, 202505, 202501])
        #expect(sections.first?.title == "2026年11月")
        #expect(sections.first(where: { $0.id == 202505 })?.checkIns.count == 2)
    }
}
