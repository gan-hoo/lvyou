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
    static let theme = "settings.theme"
    static let accent = "settings.accent"
    static let amountStyle = "settings.amountStyle"
    static let hideAmounts = "settings.hideAmounts"
    static let budgetStartDay = "settings.budgetStartDay"
    static let accountGrouping = "settings.accountGrouping"
}

/// Visual theme. Both share the same pages and tokens; only surfaces differ.
enum ThemeStyle: String, CaseIterable, Identifiable {
    case classic
    case liquidGlass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: String(localized: "Classic")
        case .liquidGlass: String(localized: "Liquid Glass")
        }
    }
}

/// How currency amounts are written.
enum AmountStyle: String, CaseIterable, Identifiable {
    case symbol
    case code

    var id: String { rawValue }

    var title: String {
        switch self {
        case .symbol: String(localized: "Symbol (¥1,234.50)")
        case .code: String(localized: "Code (CNY 1,234.50)")
        }
    }
}

enum AccountGrouping: String, CaseIterable, Identifiable {
    case type
    case currency
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type: String(localized: "By Type")
        case .currency: String(localized: "By Currency")
        case .custom: String(localized: "By Group")
        }
    }
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

    static var theme: ThemeStyle {
        ThemeStyle(rawValue: defaults.string(forKey: SettingsKey.theme) ?? "") ?? .classic
    }

    static var accentHex: String { defaults.string(forKey: SettingsKey.accent) ?? "3E7BFA" }

    static var amountStyle: AmountStyle {
        AmountStyle(rawValue: defaults.string(forKey: SettingsKey.amountStyle) ?? "") ?? .symbol
    }

    static var hideAmounts: Bool { defaults.bool(forKey: SettingsKey.hideAmounts) }

    /// First day of monthly budget periods (1…28).
    static var budgetStartDay: Int {
        let v = defaults.integer(forKey: SettingsKey.budgetStartDay)
        return v == 0 ? 1 : min(28, max(1, v))
    }

    static func uuid(forKey key: String) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    static func setUUID(_ id: UUID?, forKey key: String) {
        defaults.set(id?.uuidString, forKey: key)
    }
}
