import SwiftUI
import SwiftData

@main
struct TallyApp: App {
    private let container: ModelContainer
    @State private var lock = AppLockManager()
    @State private var toasts = ToastCenter()
    @State private var router: AppRouter
    @State private var cache: LedgerCache
    @AppStorage(SettingsKey.appearance) private var appearance: String = AppearanceMode.system.rawValue
    @AppStorage(SettingsKey.theme) private var theme: String = ThemeStyle.classic.rawValue
    @AppStorage(SettingsKey.accent) private var accent: String = "3E7BFA"
    @AppStorage(SettingsKey.amountStyle) private var amountStyle: String = AmountStyle.symbol.rawValue
    @AppStorage(SettingsKey.hideAmounts) private var hideAmounts = false

    init() {
        container = Persistence.makeContainer()
        let context = container.mainContext
        DefaultData.ensureSeeded(in: context)
        DefaultData.relocalizeBuiltInNames(in: context)
        let router = AppRouter()
        #if DEBUG
        ScreenshotMode.prepare(context)
        ScreenshotMode.configure(router)
        #endif
        // Recurring occurrences that fell due while the app was closed. Never books future dates.
        RecurringService(context: context).postDueOccurrences()
        _router = State(initialValue: router)
        _cache = State(initialValue: LedgerCache(context: context))
    }

    /// Theme, accent and amount style are read synchronously by the design system,
    /// so the view tree is rebuilt when one of them changes.
    private var styleKey: String { [theme, accent, amountStyle, hideAmounts ? "h" : "v"].joined(separator: "|") }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(styleKey)
                .environment(lock)
                .environment(toasts)
                .environment(router)
                .environment(cache)
                .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).colorScheme)
                .tint(Color(hex: accent))
        }
        .modelContainer(container)
    }
}
