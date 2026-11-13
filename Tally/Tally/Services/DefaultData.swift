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
            CategorySeed(key: "Fees", symbol: "percent", color: "7D8BA6"),
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

    /// Built-in category for transfer fees.
    static let feeCategoryKey = "Fees"

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

    /// Inserts default categories if the store is empty. Exchange rates are never
    /// invented: without user-entered or downloaded rates, foreign amounts stay
    /// "pending conversion" (demo data brings its own clearly marked demo rates).
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
        try? context.save()
    }

    /// Approximate reference rates for demo data (flagged `isDemo`, removed with the demo).
    @MainActor
    static func insertDemoRates(in context: ModelContext) {
        for (code, value) in referenceRatesFromUSD {
            let rate = ExchangeRate(
                baseCode: "USD",
                quoteCode: code,
                rate: Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0,
                effectiveDate: referenceDate,
                source: ExchangeRate.Source.reference
            )
            rate.isDemo = true
            context.insert(rate)
        }
    }

    /// Names Tally itself creates (default accounts, demo accounts and tags).
    static let builtInAccountKeys = [
        "Cash", "Bank Card", "Everyday Card", "Credit Card", "Savings",
        "AUD Travel Card", "CNY Wallet", "Imported",
    ]
    static let builtInTagKeys = ["Work", "Trip"]

    /// Renames built-in categories, accounts, tags and demo notes that still carry
    /// a default name in another language, so switching language also switches
    /// the data Tally created. Anything the user renamed or wrote is untouched.
    @MainActor
    static func relocalizeBuiltInNames(in context: ModelContext) {
        /// Maps every translation of each key to the key's name in the running language.
        func table(_ keys: [String]) -> [String: String] {
            var map: [String: String] = [:]
            for key in keys {
                let target = L10n.current(key)
                for variant in L10n.variants(of: key) where map[variant] == nil {
                    map[variant] = target
                }
            }
            return map
        }

        var changed = false
        func apply(_ name: String, _ map: [String: String]) -> String? {
            guard let target = map[name], target != name else { return nil }
            changed = true
            return target
        }

        let expense = table(expenseCategories.map(\.key))
        let income = table(incomeCategories.map(\.key))
        for category in (try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? [] {
            if let name = apply(category.name, category.kind == .expense ? expense : income) {
                category.name = name
            }
        }
        let accounts = table(builtInAccountKeys)
        for account in (try? context.fetch(FetchDescriptor<Account>())) ?? [] {
            if let name = apply(account.name, accounts) { account.name = name }
        }
        let tags = table(builtInTagKeys)
        for tag in (try? context.fetch(FetchDescriptor<Tag>())) ?? [] {
            if let name = apply(tag.name, tags) { tag.name = name }
        }
        let notes = table(DemoData.noteKeys)
        let demoEntries = (try? context.fetch(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.isDemo == true }))) ?? []
        for entry in demoEntries where !entry.note.isEmpty {
            if let note = apply(entry.note, notes) { entry.note = note }
        }
        if changed { try? context.save() }
    }
}
