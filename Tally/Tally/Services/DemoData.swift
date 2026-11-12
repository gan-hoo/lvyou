import Foundation
import SwiftData

/// Generates ~100 days of realistic sample activity. Every object created here is
/// flagged `isDemo`, surfaced with a banner, and can be removed in one tap from
/// Settings without touching the user's own records.
@MainActor
enum DemoData {
    /// Deterministic PRNG so the demo looks the same on every device.
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static func load(into context: ModelContext, base: String = AppSettings.baseCurrency, days: Int = 100, now: Date = .now) {
        DefaultData.ensureSeeded(in: context)
        let store = LedgerStore(context: context)
        let converter = store.converter()
        var rng = SeededGenerator(seed: 20_261_112)
        let cal = Calendar.current

        // Template amounts are written in CNY and scaled into the base currency.
        let factor = converter.rate(from: "CNY", to: base) ?? 1
        let baseDigits = CurrencyInfo.info(for: base).fractionDigits
        func scaled(_ cny: Double) -> Decimal {
            let raw = (Decimal(cny) * factor)
            return raw.rounded(scale: min(1, baseDigits))
        }
        func random(_ range: ClosedRange<Double>) -> Double {
            Double.random(in: range, using: &rng).rounded()
        }
        func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }

        // Categories by their built-in symbol (names are localized).
        let categories = (try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? []
        func cat(_ symbol: String, _ kind: CategoryKind) -> LedgerCategory? {
            categories.first { $0.symbolName == symbol && $0.kind == kind }
        }

        // Accounts
        var order = store.nextAccountSortOrder()
        func makeAccount(_ name: String, _ kind: AccountKind, _ currency: String, _ opening: Decimal, _ color: String) -> Account {
            let a = Account(name: name, kind: kind, currencyCode: currency, openingBalance: opening, colorHex: color, sortOrder: order, isDemo: true)
            order += 1
            context.insert(a)
            return a
        }
        let debit = makeAccount(String(localized: "Everyday Card"), .debitCard, base, scaled(12_000), "3E7BFA")
        let cash = makeAccount(String(localized: "Cash"), .cash, base, scaled(800), "4CB782")
        let credit = makeAccount(String(localized: "Credit Card"), .creditCard, base, -scaled(1_500), "EB5E8C")
        let savings = makeAccount(String(localized: "Savings"), .savings, base, scaled(50_000), "9B6DD6")
        let foreignCode = base == "AUD" ? "CNY" : "AUD"
        let isAUD = foreignCode == "AUD"
        let foreignName: String = isAUD ? String(localized: "AUD Travel Card") : String(localized: "CNY Wallet")
        let foreignKind: AccountKind = isAUD ? .debitCard : .eWallet
        let foreignOpening: Decimal = isAUD ? 300 : 2_000
        let foreign = makeAccount(foreignName, foreignKind, foreignCode, foreignOpening, "3BB5A6")
        AppSettings.setUUID(debit.id, forKey: SettingsKey.defaultAccountID)

        let work = Tag(name: String(localized: "Work"), colorHex: "4A90E2", isDemo: true)
        let trip = Tag(name: String(localized: "Trip"), colorHex: "3BB5A6", isDemo: true)
        context.insert(work)
        context.insert(trip)

        func add(_ kind: TransactionKind, _ amount: Decimal, _ day: Date, hour: Int, minute: Int? = nil,
                 account: Account, to: Account? = nil, toAmount: Decimal? = nil,
                 category: LedgerCategory? = nil, note: String = "", tags: [Tag] = []) {
            guard amount > 0 else { return }
            let m = minute ?? Int.random(in: 0...59, using: &rng)
            guard let date = cal.date(bySettingHour: hour, minute: m, second: 0, of: day), date <= now else { return }
            let e = LedgerEntry(kind: kind, amount: amount, currencyCode: account.currencyCode, date: date, note: note, isDemo: true)
            context.insert(e)
            e.account = account
            e.toAccount = to
            if let toAmount { e.toAmount = toAmount }
            e.category = category
            e.tags = tags
            store.applySnapshot(to: e, base: base, converter: converter)
        }

        let today = cal.startOfDay(for: now)
        let tripStart = cal.date(byAdding: .day, value: -38, to: today) ?? today

        for offset in stride(from: days, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = cal.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            let dom = cal.component(.day, from: day)
            let onTrip = day >= tripStart && day < (cal.date(byAdding: .day, value: 5, to: tripStart) ?? tripStart)

            // Monthly fixed items
            if dom == 1 { add(.expense, scaled(4_800), day, hour: 9, minute: 5, account: debit, category: cat("house", .expense), note: String(localized: "Rent")) }
            if dom == 5 {
                add(.expense, scaled(15), day, hour: 6, minute: 0, account: credit, category: cat("repeat", .expense), note: String(localized: "Music streaming"))
                add(.expense, scaled(30), day, hour: 6, minute: 1, account: credit, category: cat("repeat", .expense), note: String(localized: "Video streaming"))
                add(.expense, scaled(21), day, hour: 6, minute: 2, account: credit, category: cat("repeat", .expense), note: String(localized: "Cloud storage"))
            }
            if dom == 10 { add(.income, scaled(18_500), day, hour: 10, minute: 0, account: debit, category: cat("briefcase", .income), note: String(localized: "Monthly salary")) }
            if dom == 11 { add(.transfer, scaled(3_000), day, hour: 10, minute: 30, account: debit, to: savings, note: String(localized: "Monthly saving")) }
            if dom == 12 { add(.expense, scaled(random(260...420)), day, hour: 20, account: debit, category: cat("bolt", .expense), note: String(localized: "Electricity & water")) }
            if dom == 18 { add(.transfer, scaled(random(2_400...3_600)), day, hour: 21, account: debit, to: credit, note: String(localized: "Card repayment")) }
            if dom == 20 { add(.income, scaled(random(120...480)), day, hour: 9, account: savings, category: cat("chart.line.uptrend.xyaxis", .income), note: String(localized: "Interest")) }

            if onTrip {
                let fx = foreign.currencyCode
                let local = { (cny: Double) -> Decimal in
                    (converter.convertOrSame(Decimal(cny), from: "CNY", to: fx)).rounded(scale: 1)
                }
                add(.expense, local(random(120...260)), day, hour: 12, account: foreign, category: cat("fork.knife", .expense), note: String(localized: "Local lunch"), tags: [trip])
                add(.expense, local(random(40...120)), day, hour: 15, account: foreign, category: cat("tram", .expense), note: String(localized: "Ferry & train"), tags: [trip])
                if chance(0.6) { add(.expense, local(random(150...600)), day, hour: 17, account: foreign, category: cat("airplane", .expense), note: String(localized: "Sightseeing"), tags: [trip]) }
                continue
            }
            if day == cal.date(byAdding: .day, value: -2, to: tripStart) {
                let amount = scaled(5_000)
                let credited = converter.convertOrSame(amount, from: base, to: foreign.currencyCode)
                add(.transfer, amount, day, hour: 19, account: debit, to: foreign, toAmount: credited, note: String(localized: "Top up travel card"))
                add(.expense, scaled(2_380), day, hour: 20, account: credit, category: cat("airplane", .expense), note: String(localized: "Flights"), tags: [trip])
            }

            // Daily life
            if !isWeekend && chance(0.65) {
                let hour: Int = 8 + Int.random(in: 0...1, using: &rng)
                let account: Account = chance(0.7) ? debit : cash
                let note: String = chance(0.5) ? String(localized: "Flat white") : ""
                add(.expense, scaled(random(22...38)), day, hour: hour, account: account, category: cat("cup.and.saucer", .expense), note: note)
            }
            if !isWeekend && chance(0.75) {
                let team = chance(0.15)
                let range: ClosedRange<Double> = team ? 60...120 : 25...65
                let account: Account = chance(0.6) ? debit : credit
                let note: String = team ? String(localized: "Team lunch") : ""
                let tags: [Tag] = team ? [work] : []
                add(.expense, scaled(random(range)), day, hour: 12, account: account, category: cat("fork.knife", .expense), note: note, tags: tags)
            }
            let dinnerChance: Double = isWeekend ? 0.45 : 0.2
            if chance(dinnerChance) {
                let note: String = chance(0.4) ? String(localized: "Dinner with friends") : ""
                add(.expense, scaled(random(90...280)), day, hour: 19, account: credit, category: cat("fork.knife", .expense), note: note)
            }
            if dom % 4 == 0 || (isWeekend && chance(0.4)) {
                let account: Account = chance(0.5) ? debit : credit
                let note: String = chance(0.5) ? String(localized: "Weekly groceries") : ""
                add(.expense, scaled(random(90...380)), day, hour: 18, account: account, category: cat("cart", .expense), note: note)
            }
            if !isWeekend && chance(0.85) {
                add(.expense, scaled(random(4...12)), day, hour: 8, account: debit, category: cat("tram", .expense), note: String(localized: "Metro"))
            }
            if chance(0.08) {
                add(.expense, scaled(random(35...90)), day, hour: 22, account: credit, category: cat("tram", .expense), note: String(localized: "Taxi"))
            }
            if chance(0.09) {
                add(.expense, scaled(random(120...900)), day, hour: 16, account: credit, category: cat("bag", .expense))
            }
            if isWeekend && chance(0.35) {
                let note: String = chance(0.5) ? String(localized: "Movie night") : ""
                add(.expense, scaled(random(60...300)), day, hour: 20, account: credit, category: cat("gamecontroller", .expense), note: note)
            }
            if chance(0.035) {
                add(.expense, scaled(random(50...400)), day, hour: 11, account: debit, category: cat("cross.case", .expense), note: String(localized: "Pharmacy"))
            }
            if chance(0.03) {
                add(.expense, scaled(random(100...500)), day, hour: 14, account: debit, category: cat("gift", .expense))
            }
            if weekday == 6 && chance(0.25) {
                add(.income, scaled(random(600...2_400)), day, hour: 17, account: debit, category: cat("laptopcomputer", .income), note: String(localized: "Freelance project"))
            }
        }

        // Budgets
        context.insert(Budget(amount: scaled(12_000), currencyCode: base, alertThreshold: 0.8, isDemo: true))
        let budgetSeeds: [(String, Double)] = [("fork.knife", 1_800), ("cart", 1_500), ("cup.and.saucer", 600), ("bag", 1_200)]
        for (symbol, amount) in budgetSeeds {
            if let c = cat(symbol, .expense) {
                let budget = Budget(amount: scaled(amount), currencyCode: base, alertThreshold: 0.8, isDemo: true)
                context.insert(budget)
                budget.category = c
            }
        }
        try? context.save()
    }
}
