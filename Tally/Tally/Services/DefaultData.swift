import Foundation
import SwiftData

/// Built-in categories and reference exchange rates created on first launch.
enum DefaultData {
    struct CategorySeed {
        let name: String
        let symbol: String
        let color: String
    }

    static var expenseCategories: [CategorySeed] {
        [
            CategorySeed(name: String(localized: "Dining"), symbol: "fork.knife", color: "F2994A"),
            CategorySeed(name: String(localized: "Groceries"), symbol: "cart", color: "4CB782"),
            CategorySeed(name: String(localized: "Coffee"), symbol: "cup.and.saucer", color: "B08968"),
            CategorySeed(name: String(localized: "Transport"), symbol: "tram", color: "4A90E2"),
            CategorySeed(name: String(localized: "Shopping"), symbol: "bag", color: "EB5E8C"),
            CategorySeed(name: String(localized: "Housing"), symbol: "house", color: "9B6DD6"),
            CategorySeed(name: String(localized: "Utilities"), symbol: "bolt", color: "E8B730"),
            CategorySeed(name: String(localized: "Entertainment"), symbol: "gamecontroller", color: "6C7BF2"),
            CategorySeed(name: String(localized: "Health"), symbol: "cross.case", color: "EB5757"),
            CategorySeed(name: String(localized: "Education"), symbol: "book", color: "47B5D9"),
            CategorySeed(name: String(localized: "Travel"), symbol: "airplane", color: "3BB5A6"),
            CategorySeed(name: String(localized: "Subscriptions"), symbol: "repeat", color: "7D8BA6"),
            CategorySeed(name: String(localized: "Gifts"), symbol: "gift", color: "F07FA0"),
            CategorySeed(name: String(localized: "Pets"), symbol: "pawprint", color: "D98E5F"),
            CategorySeed(name: String(localized: "Other"), symbol: "ellipsis.circle", color: "8E8E93"),
        ]
    }

    static var incomeCategories: [CategorySeed] {
        [
            CategorySeed(name: String(localized: "Salary"), symbol: "briefcase", color: "4CB782"),
            CategorySeed(name: String(localized: "Bonus"), symbol: "star", color: "E8B730"),
            CategorySeed(name: String(localized: "Investments"), symbol: "chart.line.uptrend.xyaxis", color: "4A90E2"),
            CategorySeed(name: String(localized: "Side Income"), symbol: "laptopcomputer", color: "9B6DD6"),
            CategorySeed(name: String(localized: "Refunds"), symbol: "arrow.uturn.backward", color: "47B5D9"),
            CategorySeed(name: String(localized: "Gifts Received"), symbol: "gift", color: "F07FA0"),
            CategorySeed(name: String(localized: "Other Income"), symbol: "ellipsis.circle", color: "8E8E93"),
        ]
    }

    /// Approximate mid-market reference rates (1 USD = x). Users can add dated rates
    /// manually or fetch current ones; these only make conversion work out of the box.
    static let referenceRatesFromUSD: [(String, String)] = [
        ("CNY", "7.12"), ("AUD", "1.53"), ("EUR", "0.86"), ("GBP", "0.76"),
        ("JPY", "153"), ("HKD", "7.78"), ("NZD", "1.75"), ("SGD", "1.30"),
        ("CAD", "1.40"), ("KRW", "1450"), ("TWD", "31"),
    ]

    static var referenceDate: Date {
        Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .distantPast
    }

    /// Inserts default categories and reference rates if the store is empty.
    @MainActor
    static func ensureSeeded(in context: ModelContext) {
        let categoryCount = (try? context.fetchCount(FetchDescriptor<LedgerCategory>())) ?? 0
        if categoryCount == 0 {
            for (i, seed) in expenseCategories.enumerated() {
                context.insert(LedgerCategory(name: seed.name, kind: .expense, symbolName: seed.symbol, colorHex: seed.color, sortOrder: i))
            }
            for (i, seed) in incomeCategories.enumerated() {
                context.insert(LedgerCategory(name: seed.name, kind: .income, symbolName: seed.symbol, colorHex: seed.color, sortOrder: i))
            }
        }

        let rateCount = (try? context.fetchCount(FetchDescriptor<ExchangeRate>())) ?? 0
        if rateCount == 0 {
            for (code, value) in referenceRatesFromUSD {
                context.insert(ExchangeRate(
                    baseCode: "USD",
                    quoteCode: code,
                    rate: Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 1,
                    effectiveDate: referenceDate,
                    source: ExchangeRate.Source.reference
                ))
            }
        }
        try? context.save()
    }
}
