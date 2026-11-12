import SwiftUI
import SwiftData

@main
struct TallyApp: App {
    private let container: ModelContainer
    @State private var lock = AppLockManager()
    @State private var toasts = ToastCenter()
    @State private var router: AppRouter
    @AppStorage(SettingsKey.appearance) private var appearance: String = AppearanceMode.system.rawValue

    init() {
        container = Persistence.makeContainer()
        DefaultData.ensureSeeded(in: container.mainContext)
        let router = AppRouter()
        #if DEBUG
        ScreenshotMode.prepare(container.mainContext)
        ScreenshotMode.configure(router)
        #endif
        _router = State(initialValue: router)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(lock)
                .environment(toasts)
                .environment(router)
                .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).colorScheme)
                .tint(DS.Colors.accent)
        }
        .modelContainer(container)
    }
}
