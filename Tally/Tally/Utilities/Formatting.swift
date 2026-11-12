import Foundation

/// Central place for money formatting so every screen renders amounts identically.
enum MoneyFormat {
    static let mask = "••••"

    /// Formats money in the user's amount style. Masked when "Hide Amounts" is on,
    /// unless `reveal` is set (amount entry fields must always show what is typed).
    static func string(
        _ value: Decimal,
        code: String,
        showPlusSign: Bool = false,
        fractionDigits: Int? = nil,
        reveal: Bool = false
    ) -> String {
        if AppSettings.hideAmounts && !reveal { return mask }
        let digits = fractionDigits ?? CurrencyInfo.info(for: code).fractionDigits
        switch AppSettings.amountStyle {
        case .symbol:
            var style = Decimal.FormatStyle.Currency(code: code, locale: .current)
                .precision(.fractionLength(digits))
            if showPlusSign {
                style = style.sign(strategy: .always(showZero: false))
            }
            return value.formatted(style)
        case .code:
            var number = Decimal.FormatStyle(locale: .current).precision(.fractionLength(digits))
            if showPlusSign {
                number = number.sign(strategy: .always(includingZero: false))
            }
            return code + " " + value.formatted(number)
        }
    }

    /// Signed amount as shown in lists: "-¥32.00" for spending, "+¥1,200.00" for money in.
    static func signed(_ value: Decimal, code: String, kind: TransactionKind) -> String {
        switch kind {
        case .expense: string(-value.magnitudeValue, code: code)
        case .income, .refund: string(value.magnitudeValue, code: code, showPlusSign: true)
        case .transfer: string(value.magnitudeValue, code: code)
        case .adjustment: string(value, code: code, showPlusSign: true)
        }
    }

    /// Number without currency symbol, e.g. "1,234.50".
    static func plain(_ value: Decimal, fractionDigits: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// Short axis labels for charts: "1.2K", "3万".
    static func compact(_ value: Double) -> String {
        if AppSettings.hideAmounts { return "" }
        return value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }

    static func percent(_ fraction: Double, digits: Int = 0) -> String {
        fraction.formatted(.percent.precision(.fractionLength(digits)))
    }

    static func rate(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(2...6)))
    }
}

extension Date {
    /// "Wednesday, 12 Nov" / "11月12日 星期三"
    var dayHeaderText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return String(localized: "Today") }
        if calendar.isDateInYesterday(self) { return String(localized: "Yesterday") }
        if calendar.isDate(self, equalTo: .now, toGranularity: .year) {
            return formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
        }
        return formatted(.dateTime.year().month(.abbreviated).day().weekday(.abbreviated))
    }

    /// "November 2026" / "2026年11月"
    var monthTitle: String { formatted(.dateTime.year().month(.wide)) }

    var shortMonthTitle: String { formatted(.dateTime.month(.abbreviated)) }

    var yearTitle: String { formatted(.dateTime.year()) }

    var shortDateText: String { formatted(date: .abbreviated, time: .omitted) }

    var timeText: String { formatted(date: .omitted, time: .shortened) }
}
