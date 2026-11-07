import Testing
import Foundation
import SwiftData
import CoreLocation
@testable import TravelFootprints

@MainActor
struct CheckInStoreTests {
    let container: ModelContainer
    let store: CheckInStore

    init() {
        container = TestFixtures.makeContainer()
        store = CheckInStore(context: container.mainContext)
    }

    private func location(near candidate: PlaceCandidate, accuracy: Double = 10) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: candidate.latitude + 0.0003, longitude: candidate.longitude),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10, timestamp: .now
        )
    }

    private func placeCount() throws -> Int {
        try container.mainContext.fetchCount(FetchDescriptor<Place>())
    }

    private func checkInCount() throws -> Int {
        try container.mainContext.fetchCount(FetchDescriptor<CheckIn>())
    }

    @Test func gpsCheckInCreatesPlaceAndVerifiedRecord() throws {
        let candidate = TestFixtures.operaHouse
        let checkIn = try store.recordGPSCheckIn(for: candidate, location: location(near: candidate), distance: 33)

        #expect(checkIn.method == .gpsVerified)
        #expect(checkIn.gpsLatitude != nil)
        #expect(checkIn.gpsLongitude != nil)
        #expect(checkIn.gpsHorizontalAccuracy == 10)
        #expect(checkIn.distanceFromPlace == 33)
        #expect(checkIn.timeZoneIdentifier == "Australia/Sydney")
        #expect(checkIn.place?.name == "Sydney Opera House")
        #expect(checkIn.place?.checkInRadius == 200)
        #expect(try placeCount() == 1)
    }

    @Test func repeatedCheckInsReuseSamePlace() throws {
        let candidate = TestFixtures.operaHouse
        try store.recordGPSCheckIn(for: candidate, location: location(near: candidate), distance: 30)
        try store.recordGPSCheckIn(for: candidate, location: location(near: candidate), distance: 40)

        #expect(try placeCount() == 1)
        #expect(try checkInCount() == 2)
        let place = try #require(try store.existingPlace(matching: candidate))
        #expect(place.visitCount == 2)
    }

    @Test func placeWithoutIdentifierMatchesByNameAndProximity() throws {
        let candidate = TestFixtures.tokyoTower
        try store.recordManualCheckIn(for: candidate, visitedAt: TestFixtures.date("2025-05-01T03:00:00Z"), timeZone: .gmt)

        var shifted = candidate
        shifted.latitude += 0.0002 // ~22 米
        #expect(try store.existingPlace(matching: shifted) != nil)

        var farAway = candidate
        farAway.latitude += 0.01 // ~1.1 公里
        #expect(try store.existingPlace(matching: farAway) == nil)
    }

    @Test func manualCheckInIsNeverMarkedAsGPS() throws {
        let visitedAt = TestFixtures.date("2024-12-31T23:30:00Z")
        let paris = try #require(TimeZone(identifier: "Europe/Paris"))
        let checkIn = try store.recordManualCheckIn(
            for: TestFixtures.eiffelTower, visitedAt: visitedAt, timeZone: paris, note: "  跨年夜  "
        )

        #expect(checkIn.method == .manual)
        #expect(!checkIn.isGPSVerified)
        #expect(checkIn.gpsCoordinate == nil)
        #expect(checkIn.distanceFromPlace == nil)
        #expect(checkIn.visitedAt == visitedAt)
        #expect(checkIn.timeZoneIdentifier == "Europe/Paris")
        #expect(checkIn.note == "跨年夜")
        // 巴黎当地时间已是 2025 年。
        #expect(checkIn.localYear == 2025)
    }

    @Test func manualCheckInRejectsFutureDate() throws {
        let now = Date()
        #expect(throws: CheckInStoreError.visitDateInFuture) {
            try store.recordManualCheckIn(
                for: TestFixtures.eiffelTower,
                visitedAt: now.addingTimeInterval(3_600),
                timeZone: .gmt,
                now: now
            )
        }
        #expect(try checkInCount() == 0)
    }

    @Test func deletingLastCheckInAndPurgingRemovesPlace() throws {
        let candidate = TestFixtures.operaHouse
        let first = try store.recordGPSCheckIn(for: candidate, location: location(near: candidate), distance: 30)
        let second = try store.recordGPSCheckIn(for: candidate, location: location(near: candidate), distance: 30)

        try store.delete(first)
        try store.purgeOrphanPlaces()
        #expect(try placeCount() == 1)
        #expect(try checkInCount() == 1)

        try store.delete(second)
        try store.purgeOrphanPlaces()
        #expect(try placeCount() == 0)
        #expect(try checkInCount() == 0)
    }
}
