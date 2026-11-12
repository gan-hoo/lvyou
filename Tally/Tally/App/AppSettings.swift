import SwiftUI

/// `UserDefaults` keys for non-sensitive preferences.
/// Security-relevant preferences live in the Keychain (see `AppLockManager`).
enum SettingsKey {
    static let baseCurrency = "settings.baseCurrency"
    static let appearance = "settings.appearance"
    static let hapticsEnabled = "settings.haptics"
    static let hasCompletedOnboarding = "settings.onboarded"
    static let defaultAccountID = "settings.defaultAccountID"
    static let lastExpenseCategoryID = "settings.lastExpenseCategory"
    static let lastIncomeCategoryID = "settings.lastIncomeCategory"
    static let budgetAlertsEnabled = "settings.budgetAlerts"
    static let budgetNotified = "settings.budgetNotified"
    static let showsDemoBanner = "settings.demoBanner"
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Synchronous accessors for code outside the view hierarchy.
enum AppSettings {
    static var defaults: UserDefaults { .standard }

    static var baseCurrency: String {
        get { defaults.string(forKey: SettingsKey.baseCurrency) ?? CurrencyInfo.suggestedBase }
        set { defaults.set(newValue, forKey: SettingsKey.baseCurrency) }
    }

    static var hapticsEnabled: Bool {
        defaults.object(forKey: SettingsKey.hapticsEnabled) as? Bool ?? true
    }

    static var budgetAlertsEnabled: Bool {
        defaults.object(forKey: SettingsKey.budgetAlertsEnabled) as? Bool ?? true
    }

    static func uuid(forKey key: String) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    static func setUUID(_ id: UUID?, forKey key: String) {
        defaults.set(id?.uuidString, forKey: key)
    }
}
