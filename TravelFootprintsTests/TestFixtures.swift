import Foundation
import SwiftData
@testable import TravelFootprints

enum TestFixtures {
    static let operaHouse = PlaceCandidate(
        name: "Sydney Opera House",
        address: "Bennelong Point, Sydney NSW 2000, Australia",
        locality: "Sydney",
        administrativeArea: "NSW",
        country: "澳大利亚",
        countryCode: "AU",
        latitude: -33.856784,
        longitude: 151.215297,
        mapItemIdentifier: "I-OPERA-HOUSE",
        timeZoneIdentifier: "Australia/Sydney"
    )

    static let tokyoTower = PlaceCandidate(
        name: "东京塔",
        locality: "东京",
        country: "日本",
        countryCode: "JP",
        latitude: 35.658581,
        longitude: 139.745433,
        timeZoneIdentifier: "Asia/Tokyo"
    )

    static let sensoji = PlaceCandidate(
        name: "浅草寺",
        locality: "东京",
        country: "日本",
        countryCode: "JP",
        latitude: 35.714765,
        longitude: 139.796655,
        timeZoneIdentifier: "Asia/Tokyo"
    )

    static let eiffelTower = PlaceCandidate(
        name: "埃菲尔铁塔",
        locality: "巴黎",
        country: "法国",
        countryCode: "FR",
        latitude: 48.858370,
        longitude: 2.294481,
        timeZoneIdentifier: "Europe/Paris"
    )

    static func date(_ iso: String) -> Date {
        guard let date = ISO8601DateFormatter().date(from: iso) else {
            preconditionFailure("Invalid ISO date \(iso)")
        }
        return date
    }

    @MainActor
    static func makeContainer() -> ModelContainer {
        PersistenceController.makeContainer(inMemory: true)
    }
}
