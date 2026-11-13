import Foundation

/// In-app language choice. iOS normally follows the phone's language; this lets
/// people run Tally in Chinese on an English (or any other) iPhone, and vice versa.
///
/// The choice is written to the app's `AppleLanguages` preference, which iOS reads
/// at launch, so it applies consistently to every string, date and number after
/// Tally is reopened.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    var id: String { rawValue }

    /// Language names are shown in their own language so they are recognisable in any UI language.
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        }
    }

    static let preferenceKey = "settings.language"
    private static let appleLanguagesKey = "AppleLanguages"

    static var selected: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .system
    }

    /// The localization this launch is actually running in ("zh-Hans", "zh-Hant" or "en").
    static var running: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Stores the choice. Returns true when Tally must be reopened for it to take effect.
    @discardableResult
    static func select(_ language: AppLanguage) -> Bool {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: preferenceKey)
        switch language {
        case .system:
            defaults.removeObject(forKey: appleLanguagesKey)
            return true
        default:
            defaults.set([language.rawValue], forKey: appleLanguagesKey)
            return language.rawValue != running
        }
    }
}

/// Locale for every date, number and currency Tally formats: the language Tally is
/// running in, combined with the phone's region. Without this, an iPhone set to
/// English (Australia) running Tally in Chinese showed Chinese text with English
/// month names ("November 2026") and English currency symbols.
enum AppLocale {
    static let current: Locale = make()

    static func make(running: String = AppLanguage.running, system: Locale = .current) -> Locale {
        let wanted = Locale.Language(identifier: running)
        let have = system.language
        if have.languageCode == wanted.languageCode {
            // Same language: keep the system locale and the user's format preferences,
            // unless the script differs (Simplified vs Traditional Chinese).
            guard let script = wanted.script else { return system }
            if have.maximalIdentifier.contains(script.identifier) { return system }
        }
        if let region = system.region?.identifier {
            return Locale(identifier: running + "_" + region)
        }
        return Locale(identifier: running)
    }
}

/// Looks up strings in a specific localization, independent of the running language.
enum L10n {
    static let supported = ["en", "zh-Hans", "zh-Hant"]

    private static let bundles: [String: Bundle] = {
        var result: [String: Bundle] = [:]
        for code in supported {
            if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) {
                result[code] = bundle
            }
        }
        return result
    }()

    static func string(_ key: String, language: String) -> String {
        bundles[language]?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    /// Every translation of a key, including the key itself (the English source).
    static func variants(of key: String) -> Set<String> {
        var set: Set<String> = [key]
        for code in supported { set.insert(string(key, language: code)) }
        return set
    }

    static func current(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }
}
