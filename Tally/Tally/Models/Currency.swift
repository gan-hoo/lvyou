import Foundation

/// Static metadata for the currencies the app supports.
struct CurrencyInfo: Identifiable, Hashable, Sendable {
    let code: String
    let symbol: String
    let fractionDigits: Int

    var id: String { code }

    /// Localized display name supplied by the system (e.g. "Australian Dollar" / "澳大利亚元").
    var localizedName: String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    static let all: [CurrencyInfo] = [
        CurrencyInfo(code: "CNY", symbol: "¥", fractionDigits: 2),
        CurrencyInfo(code: "AUD", symbol: "A$", fractionDigits: 2),
        CurrencyInfo(code: "USD", symbol: "$", fractionDigits: 2),
        CurrencyInfo(code: "EUR", symbol: "€", fractionDigits: 2),
        CurrencyInfo(code: "GBP", symbol: "£", fractionDigits: 2),
        CurrencyInfo(code: "JPY", symbol: "¥", fractionDigits: 0),
        CurrencyInfo(code: "HKD", symbol: "HK$", fractionDigits: 2),
        CurrencyInfo(code: "NZD", symbol: "NZ$", fractionDigits: 2),
        CurrencyInfo(code: "SGD", symbol: "S$", fractionDigits: 2),
        CurrencyInfo(code: "CAD", symbol: "C$", fractionDigits: 2),
        CurrencyInfo(code: "KRW", symbol: "₩", fractionDigits: 0),
        CurrencyInfo(code: "TWD", symbol: "NT$", fractionDigits: 2),
    ]

    private static let byCode: [String: CurrencyInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    static func info(for code: String) -> CurrencyInfo {
        byCode[code] ?? CurrencyInfo(code: code, symbol: code, fractionDigits: 2)
    }

    static func isSupported(_ code: String) -> Bool { byCode[code] != nil }

    /// Picks a sensible default base currency from the user's region.
    static var suggestedBase: String {
        let code = Locale.current.currency?.identifier ?? "CNY"
        return isSupported(code) ? code : "CNY"
    }
}
