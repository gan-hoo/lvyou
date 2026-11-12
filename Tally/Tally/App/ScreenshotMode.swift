import Foundation
import SwiftData

#if DEBUG
/// Debug-only launch hooks used by CI to capture simulator screenshots:
///
///     -TallyScreenshotMode            load demo data (first launch) and skip onboarding
///     -TallyTab statistics            start on a tab (home|transactions|statistics|budget|settings)
///     -TallyOpenEntry                 open the quick-entry sheet
enum ScreenshotMode {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isEnabled: Bool { arguments.contains("-TallyScreenshotMode") }

    static var initialTab: AppTab? {
        guard let i = arguments.firstIndex(of: "-TallyTab"), i + 1 < arguments.count else { return nil }
        switch arguments[i + 1] {
        case "transactions": return .transactions
        case "statistics": return .statistics
        case "budget": return .budget
        case "settings": return .settings
        default: return .home
        }
    }

    static var opensEntry: Bool { arguments.contains("-TallyOpenEntry") }

    @MainActor
    static func prepare(_ context: ModelContext) {
        guard isEnabled else { return }
        let defaults = UserDefaults.standard
        if defaults.string(forKey: SettingsKey.baseCurrency) == nil {
            defaults.set("CNY", forKey: SettingsKey.baseCurrency)
        }
        if ((try? context.fetchCount(FetchDescriptor<Account>())) ?? 0) == 0 {
            DemoData.load(into: context, base: AppSettings.baseCurrency)
        }
        defaults.set(true, forKey: SettingsKey.hasCompletedOnboarding)
    }

    @MainActor
    static func configure(_ router: AppRouter) {
        guard isEnabled else { return }
        if let tab = initialTab { router.selectedTab = tab }
        if opensEntry { router.addEntry() }
    }
}
#endif
