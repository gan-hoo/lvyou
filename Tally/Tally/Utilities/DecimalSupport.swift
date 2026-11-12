import Foundation

/// Lossless `Decimal` <-> `String` storage codec.
///
/// Money is persisted as a POSIX decimal string rather than a native SwiftData
/// `Decimal` attribute so the exact value round-trips regardless of how the
/// underlying store represents numbers.
enum DecimalCodec {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func encode(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: posix)
    }

    static func decode(_ string: String?) -> Decimal {
        guard let string, !string.isEmpty else { return 0 }
        return Decimal(string: string, locale: posix) ?? 0
    }

    /// Parses user / CSV supplied text. Accepts "1,234.50", "1234,50", "-12", "¥12.3".
    static func parseLenient(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        s = s.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" || $0 == "+" }
        if s.hasPrefix("-") { negative.toggle(); s.removeFirst() }
        if s.hasPrefix("+") { s.removeFirst() }
        let hasDot = s.contains(".")
        let commaCount = s.filter { $0 == "," }.count
        if hasDot {
            s = s.replacingOccurrences(of: ",", with: "")
        } else if commaCount == 1, let idx = s.firstIndex(of: ","), s.distance(from: idx, to: s.endIndex) <= 3 {
            // "12,50" -> decimal comma
            s = s.replacingOccurrences(of: ",", with: ".")
        } else {
            s = s.replacingOccurrences(of: ",", with: "")
        }
        guard !s.isEmpty, let value = Decimal(string: s, locale: posix) else { return nil }
        return negative ? -value : value
    }
}

extension Decimal {
    /// Rounds using banker-safe "plain" rounding to the given number of fraction digits.
    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    var isNegative: Bool { self < 0 }

    var magnitudeValue: Decimal { self < 0 ? -self : self }

    /// Number of digits after the decimal separator in the canonical representation.
    var fractionDigitCount: Int {
        let s = DecimalCodec.encode(self)
        guard let dot = s.firstIndex(of: ".") else { return 0 }
        return s.distance(from: s.index(after: dot), to: s.endIndex)
    }
}

extension Sequence {
    func sum(_ value: (Element) -> Decimal) -> Decimal {
        reduce(Decimal(0)) { $0 + value($1) }
    }
}
