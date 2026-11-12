import Foundation
import SwiftData

/// Built-in categories and reference exchange rates created on first launch.
enum DefaultData {
    /// `key` is the English source string; the stored name is its translation
    /// in the running language (see `relocalizeBuiltInNames`).
    struct CategorySeed {
        let key: String
        let symbol: String
        let color: String

        var name: String { L10n.current(key) }
    }

    static let expenseCategories: [CategorySeed] = {
        return [
            CategorySeed(key: "Dining", symbol: "fork.knife", color: "F2994A"),
            CategorySeed(key: "Groceries", symbol: "cart", color: "4CB782"),
            CategorySeed(key: "Coffee", symbol: "cup.and.saucer", color: "B08968"),
            CategorySeed(key: "Transport", symbol: "tram", color: "4A90E2"),
            CategorySeed(key: "Shopping", symbol: "bag", color: "EB5E8C"),
            CategorySeed(key: "Housing", symbol: "house", color: "9B6DD6"),
            CategorySeed(key: "Utilities", symbol: "bolt", color: "E8B730"),
            CategorySeed(key: "Entertainment", symbol: "gamecontroller", color: "6C7BF2"),
            CategorySeed(key: "Health", symbol: "cross.case", color: "EB5757"),
            CategorySeed(key: "Education", symbol: "book", color: "47B5D9"),
            CategorySeed(key: "Travel", symbol: "airplane", color: "3BB5A6"),
            CategorySeed(key: "Subscriptions", symbol: "repeat", color: "7D8BA6"),
            CategorySeed(key: "Gifts", symbol: "gift", color: "F07FA0"),
            CategorySeed(key: "Pets", symbol: "pawprint", color: "D98E5F"),
            CategorySeed(key: "Other", symbol: "ellipsis.circle", color: "8E8E93"),
        ]
    }()

    static let incomeCategories: [CategorySeed] = {
        return [
            CategorySeed(key: "Salary", symbol: "briefcase", color: "4CB782"),
            CategorySeed(key: "Bonus", symbol: "star", color: "E8B730"),
            CategorySeed(key: "Investments", symbol: "chart.line.uptrend.xyaxis", color: "4A90E2"),
            CategorySeed(key: "Side Income", symbol: "laptopcomputer", color: "9B6DD6"),
            CategorySeed(key: "Refunds", symbol: "arrow.uturn.backward", color: "47B5D9"),
            CategorySeed(key: "Gifts Received", symbol: "gift", color: "F07FA0"),
            CategorySeed(key: "Other Income", symbol: "ellipsis.circle", color: "8E8E93"),
        ]
    }()

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

    /// Names Tally itself creates (default accounts, demo accounts and tags).
    static let builtInAccountKeys = [
        "Cash", "Bank Card", "Everyday Card", "Credit Card", "Savings",
        "AUD Travel Card", "CNY Wallet", "Imported",
    ]
    static let builtInTagKeys = ["Work", "Trip"]

    /// Renames built-in categories, accounts and tags that still carry a default
    /// name in another language, so switching language also switches the data
    /// Tally created. Anything the user renamed is left untouched.
    @MainActor
    static func relocalizeBuiltInNames(in context: ModelContext) {
        var changed = false

        func relocalize(_ name: String, keys: [String]) -> String? {
            for key in keys where L10n.variants(of: key).contains(name) {
                let target = L10n.current(key)
                return target == name ? nil : target
            }
            return nil
        }

        let expenseKeys = expenseCategories.map(\.key)
        let incomeKeys = incomeCategories.map(\.key)
        for category in (try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? [] {
            let keys = category.kind == .expense ? expenseKeys : incomeKeys
            if let name = relocalize(category.name, keys: keys) {
                category.name = name
                changed = true
            }
        }
        for account in (try? context.fetch(FetchDescriptor<Account>())) ?? [] {
            if let name = relocalize(account.name, keys: builtInAccountKeys) {
                account.name = name
                changed = true
            }
        }
        for tag in (try? context.fetch(FetchDescriptor<Tag>())) ?? [] {
            if let name = relocalize(tag.name, keys: builtInTagKeys) {
                tag.name = name
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}
