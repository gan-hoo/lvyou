import SwiftUI
import SwiftData

@main
struct TravelFootprintsApp: App {
    @State private var locationService = LocationService()
    private let modelContainer = PersistenceController.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(locationService)
        }
        .modelContainer(modelContainer)
    }
}
