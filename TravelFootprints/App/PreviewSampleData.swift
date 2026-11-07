#if DEBUG
import Foundation
import SwiftData

/// 仅用于 Xcode 预览的内存数据，不参与正式功能。
@MainActor
enum PreviewSampleData {
    static let container: ModelContainer = {
        let container = PersistenceController.makeContainer(inMemory: true)
        let store = CheckInStore(context: container.mainContext)
        for (candidate, daysAgo) in samples {
            _ = try? store.recordManualCheckIn(
                for: candidate,
                visitedAt: Date.now.addingTimeInterval(-Double(daysAgo) * 86_400),
                timeZone: candidate.timeZone ?? .current,
                note: daysAgo == 3 ? "傍晚的海港非常美。" : ""
            )
        }
        return container
    }()

    static let operaHouse = PlaceCandidate(
        name: "Sydney Opera House",
        address: "Bennelong Point, Sydney NSW 2000, Australia",
        locality: "Sydney",
        administrativeArea: "NSW",
        country: "澳大利亚",
        countryCode: "AU",
        latitude: -33.856784,
        longitude: 151.215297,
        pointOfInterestCategory: "MKPOICategoryTheater",
        timeZoneIdentifier: "Australia/Sydney"
    )

    static let tokyoTower = PlaceCandidate(
        name: "东京塔",
        address: "4 Chome-2-8 Shibakoen, Minato City, Tokyo, Japan",
        locality: "东京",
        administrativeArea: "东京都",
        country: "日本",
        countryCode: "JP",
        latitude: 35.658581,
        longitude: 139.745433,
        timeZoneIdentifier: "Asia/Tokyo"
    )

    static let eiffelTower = PlaceCandidate(
        name: "埃菲尔铁塔",
        address: "Champ de Mars, 5 Av. Anatole France, 75007 Paris, France",
        locality: "巴黎",
        administrativeArea: "法兰西岛",
        country: "法国",
        countryCode: "FR",
        latitude: 48.858370,
        longitude: 2.294481,
        timeZoneIdentifier: "Europe/Paris"
    )

    private static let samples: [(PlaceCandidate, Int)] = [
        (operaHouse, 3),
        (operaHouse, 400),
        (tokyoTower, 40),
        (eiffelTower, 200)
    ]
}
#endif
