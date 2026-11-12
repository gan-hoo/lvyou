import Foundation
import SwiftData
import Testing
@testable import Tally

@MainActor
struct LedgerTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    private func makeCategory(_ kind: CategoryKind = .expense, name: String = "Food") -> LedgerCategory {
        let c = LedgerCategory(name: name, kind: kind, symbolName: "fork.knife", colorHex: "F2994A", sortOrder: 0)
        context.insert(c)
        return c
    }

    private func addRate(_ base: String, _ quote: String, _ rate: String, _ date: Date) {
        context.insert(ExchangeRate(baseCode: base, quoteCode: quote, rate: dec(rate), effectiveDate: date))
    }

    // MARK: Balances

    @Test func balancesAreDerivedFromOpeningBalanceAndEntries() throws {
        let store = LedgerStore(context: context)
        let food = makeCategory()
        let salary = makeCategory(.income, name: "Salary")
        let card = Account(name: "Card", kind: .debitCard, currencyCode: "CNY", openingBalance: 1000)
        let savings = Account(name: "Savings", kind: .savings, currencyCode: "CNY", openingBalance: 0)
        context.insert(card); context.insert(savings)

        try store.save(EntryInput(kind: .expense, amount: dec("35.50"), date: .now, note: "", account: card, category: food, tags: []), baseCurrency: "CNY")
        try store.save(EntryInput(kind: .income, amount: 5000, date: .now, note: "", account: card, category: salary, tags: []), baseCurrency: "CNY")
        try store.save(EntryInput(kind: .transfer, amount: 2000, date: .now, note: "", account: card, toAccount: savings, tags: []), baseCurrency: "CNY")

        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        let math = LedgerMath(base: "CNY", converter: CurrencyConverter(points: []))
        let balances = math.balances(accounts: [card, savings], entries: entries)
        #expect(balances[card.id] == dec("3964.5"))
        #expect(balances[savings.id] == 2000)

        let summary = math.summary(entries)
        #expect(summary.income == 5000)
        #expect(summary.expense == dec("35.5"))
        #expect(summary.count == 3)
    }

    @Test func crossCurrencyTransferCreditsConvertedAmount() throws {
        addRate("AUD", "CNY", "4.70", day(2025, 1, 1))
        let store = LedgerStore(context: context)
        let cny = Account(name: "CNY", kind: .debitCard, currencyCode: "CNY", openingBalance: 10_000)
        let aud = Account(name: "AUD", kind: .debitCard, currencyCode: "AUD", openingBalance: 0)
        context.insert(cny); context.insert(aud)

        let entry = try store.save(EntryInput(kind: .transfer, amount: 470, date: day(2025, 3, 1), note: "", account: cny, toAccount: aud, tags: []), baseCurrency: "CNY")
        #expect(entry.toAmount == 100)

        let manual = try store.save(EntryInput(kind: .transfer, amount: 470, date: day(2025, 3, 2), note: "", account: cny, toAccount: aud, toAmount: dec("99.10"), tags: []), baseCurrency: "CNY")
        #expect(manual.toAmount == dec("99.1"))

        let math = LedgerMath(base: "CNY", rates: try context.fetch(FetchDescriptor<ExchangeRate>()))
        let balances = math.balances(accounts: [cny, aud], entries: try context.fetch(FetchDescriptor<LedgerEntry>()))
        #expect(balances[cny.id] == 9060)
        #expect(balances[aud.id] == dec("199.1"))
    }

    // MARK: Historical rates

    @Test func snapshotUsesHistoricalRateAndNeverDrifts() throws {
        addRate("USD", "CNY", "7.00", day(2025, 1, 1))
        let store = LedgerStore(context: context)
        let food = makeCategory()
        let usd = Account(name: "USD", kind: .debitCard, currencyCode: "USD")
        context.insert(usd)

        let entry = try store.save(EntryInput(kind: .expense, amount: 10, date: day(2025, 2, 1), note: "", account: usd, category: food, tags: []), baseCurrency: "CNY")
        #expect(entry.rateToBase == 7)
        #expect(entry.baseAmount == 70)

        // A newer rate (or even a correction dated earlier) must not rewrite the saved snapshot.
        addRate("USD", "CNY", "7.30", day(2025, 1, 15))
        try context.save()
        let math = LedgerMath(base: "CNY", rates: try context.fetch(FetchDescriptor<ExchangeRate>()))
        #expect(math.value(entry) == 70)

        // Editing only the note keeps the snapshot.
        _ = try store.save(EntryInput(kind: .expense, amount: 10, date: day(2025, 2, 1), note: "lunch", account: usd, category: food, tags: []), editing: entry, baseCurrency: "CNY")
        #expect(entry.baseAmount == 70)
        #expect(entry.note == "lunch")

        // Changing the amount re-snapshots with the rate in effect on that date.
        _ = try store.save(EntryInput(kind: .expense, amount: 20, date: day(2025, 2, 1), note: "lunch", account: usd, category: food, tags: []), editing: entry, baseCurrency: "CNY")
        #expect(entry.rateToBase == dec("7.3"))
        #expect(entry.baseAmount == 146)
    }

    @Test func changingBaseCurrencyConvertsWithHistoricalRates() throws {
        addRate("USD", "CNY", "7", day(2025, 1, 1))
        addRate("USD", "AUD", "1.5", day(2025, 1, 1))
        let store = LedgerStore(context: context)
        let food = makeCategory()
        let cny = Account(name: "CNY", kind: .cash, currencyCode: "CNY")
        context.insert(cny)
        let entry = try store.save(EntryInput(kind: .expense, amount: 700, date: day(2025, 2, 1), note: "", account: cny, category: food, tags: []), baseCurrency: "CNY")
        #expect(entry.baseAmount == 700)

        let audMath = LedgerMath(base: "AUD", rates: try context.fetch(FetchDescriptor<ExchangeRate>()))
        #expect(audMath.value(entry) == 150)
    }

    // MARK: Validation

    @Test func rejectsInvalidInput() {
        let store = LedgerStore(context: context)
        let a = Account(name: "A", kind: .cash, currencyCode: "CNY")
        context.insert(a)
        #expect(throws: LedgerError.amountMustBePositive) {
            try store.save(EntryInput(kind: .expense, amount: 0, date: .now, note: "", account: a, tags: []), baseCurrency: "CNY")
        }
        #expect(throws: LedgerError.accountRequired) {
            try store.save(EntryInput(kind: .expense, amount: 5, date: .now, note: "", account: nil, tags: []), baseCurrency: "CNY")
        }
        #expect(throws: LedgerError.sameAccountTransfer) {
            try store.save(EntryInput(kind: .transfer, amount: 5, date: .now, note: "", account: a, toAccount: a, tags: []), baseCurrency: "CNY")
        }
    }

    @Test func roundsAmountToAccountCurrency() throws {
        let store = LedgerStore(context: context)
        let jpy = Account(name: "JPY", kind: .cash, currencyCode: "JPY")
        context.insert(jpy)
        let e = try store.save(EntryInput(kind: .expense, amount: dec("1234.6"), date: .now, note: "", account: jpy, tags: []), baseCurrency: "JPY")
        #expect(e.amount == 1235)
    }

    @Test func deletingAccountRemovesItsEntries() throws {
        let store = LedgerStore(context: context)
        let a = Account(name: "A", kind: .cash, currencyCode: "CNY", openingBalance: 100)
        let b = Account(name: "B", kind: .cash, currencyCode: "CNY")
        context.insert(a); context.insert(b)
        try store.save(EntryInput(kind: .expense, amount: 5, date: .now, note: "", account: a, tags: []), baseCurrency: "CNY")
        try store.save(EntryInput(kind: .transfer, amount: 5, date: .now, note: "", account: b, toAccount: a, tags: []), baseCurrency: "CNY")
        try store.save(EntryInput(kind: .expense, amount: 7, date: .now, note: "", account: b, tags: []), baseCurrency: "CNY")
        store.deleteAccount(a)
        let remaining = try context.fetch(FetchDescriptor<LedgerEntry>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.amount == 7)
    }

    // MARK: Budgets

    @Test func budgetLevelsFollowThreshold() throws {
        let store = LedgerStore(context: context)
        let food = makeCategory()
        let cash = Account(name: "Cash", kind: .cash, currencyCode: "CNY")
        context.insert(cash)
        context.insert(Budget(amount: 1000, currencyCode: "CNY", alertThreshold: 0.8))
        let foodBudget = Budget(amount: 100, currencyCode: "CNY", alertThreshold: 0.8)
        context.insert(foodBudget)
        foodBudget.category = food
        try store.save(EntryInput(kind: .expense, amount: 120, date: .now, note: "", account: cash, category: food, tags: []), baseCurrency: "CNY")
        try store.save(EntryInput(kind: .expense, amount: 700, date: .now, note: "", account: cash, tags: []), baseCurrency: "CNY")

        let math = LedgerMath(base: "CNY", converter: CurrencyConverter(points: []))
        let overview = BudgetEvaluator(math: math).overview(
            budgets: try context.fetch(FetchDescriptor<Budget>()),
            entries: try context.fetch(FetchDescriptor<LedgerEntry>()),
            period: .month()
        )
        #expect(overview.overall?.spent == 820)
        #expect(overview.overall?.level == .approaching)
        #expect(overview.categories.first?.level == .exceeded)
        #expect(overview.categories.first?.remaining == -20)
        #expect(overview.mostUrgent?.id == overview.categories.first?.id)
    }

    // MARK: Statistics

    @Test func categoryBreakdownSumsToOne() throws {
        let store = LedgerStore(context: context)
        let food = makeCategory(name: "Food")
        let fun = makeCategory(name: "Fun")
        let cash = Account(name: "Cash", kind: .cash, currencyCode: "CNY")
        context.insert(cash)
        try store.save(EntryInput(kind: .expense, amount: 30, date: .now, note: "", account: cash, category: food, tags: []), baseCurrency: "CNY")
        try store.save(EntryInput(kind: .expense, amount: 10, date: .now, note: "", account: cash, category: fun, tags: []), baseCurrency: "CNY")
        let math = LedgerMath(base: "CNY", converter: CurrencyConverter(points: []))
        let slices = math.categoryBreakdown(try context.fetch(FetchDescriptor<LedgerEntry>()), kind: .expense)
        #expect(slices.map(\.name) == ["Food", "Fun"])
        #expect(slices.first?.fraction == 0.75)
        #expect(abs(slices.reduce(0) { $0 + $1.fraction } - 1) < 0.000_001)
    }

    // MARK: Demo data

    @Test func demoDataIsFlaggedAndRemovable() throws {
        DefaultData.ensureSeeded(in: context)
        let mine = Account(name: "Mine", kind: .cash, currencyCode: "CNY")
        context.insert(mine)
        try LedgerStore(context: context).save(EntryInput(kind: .expense, amount: 1, date: .now, note: "", account: mine, tags: []), baseCurrency: "CNY")

        DemoData.load(into: context, base: "CNY")
        let all = try context.fetch(FetchDescriptor<LedgerEntry>())
        #expect(all.count > 100)
        #expect(all.filter { !$0.isDemo }.count == 1)
        #expect(all.allSatisfy { $0.date <= .now })

        LedgerStore(context: context).deleteDemoData()
        #expect(try context.fetch(FetchDescriptor<LedgerEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Account>()).map(\.name) == ["Mine"])
        #expect(try context.fetchCount(FetchDescriptor<Budget>()) == 0)
    }
}
