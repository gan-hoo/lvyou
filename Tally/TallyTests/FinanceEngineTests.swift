import Foundation
import Testing
@testable import Tally

/// Pure engine tests on value snapshots (docs/FINANCE_RULES.md).
struct FinanceEngineTests {
    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }
    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        Calendar.ledger.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private let cashID = UUID(), cardID = UUID(), savingsID = UUID(), audID = UUID(), loanID = UUID()
    private let food = UUID(), pets = UUID(), fees = UUID(), salary = UUID()

    private var accounts: [AccountValue] {
        [
            AccountValue(id: cashID, kind: .cash, currency: "CNY", openingBalance: 1_000, openingDate: .distantPast, includeInNetWorth: true, isArchived: false),
            AccountValue(id: cardID, kind: .creditCard, currency: "CNY", openingBalance: 0, openingDate: .distantPast, includeInNetWorth: true, isArchived: false),
            AccountValue(id: savingsID, kind: .savings, currency: "CNY", openingBalance: 0, openingDate: .distantPast, includeInNetWorth: true, isArchived: false),
            AccountValue(id: audID, kind: .debitCard, currency: "AUD", openingBalance: 100, openingDate: .distantPast, includeInNetWorth: true, isArchived: false),
            AccountValue(id: loanID, kind: .loan, currency: "CNY", openingBalance: -5_000, openingDate: .distantPast, includeInNetWorth: true, isArchived: false),
        ]
    }

    private var rates: [RatePoint] { [RatePoint(base: "AUD", quote: "CNY", rate: dec("4.70"), date: day(2025, 1, 1))] }
    private var engine: FinanceEngine { FinanceEngine(base: "CNY", rates: rates) }
    private var march: Period { Period.month(day(2025, 3, 15)) }

    @Test func incomeAndExpenseMoveBalancesAndReports() {
        let entries = [
            EntryValue(kind: .income, amount: 500, currency: "CNY", date: day(2025, 3, 1), accountID: cashID, categoryID: salary),
            EntryValue(kind: .expense, amount: dec("35.5"), currency: "CNY", date: day(2025, 3, 2), accountID: cashID, categoryID: food),
        ]
        let b = engine.balances(accounts: accounts, entries: entries)
        #expect(b[cashID] == dec("1464.5"))
        let r = engine.report(entries, in: march)
        #expect(r.income == 500)
        #expect(r.expense == dec("35.5"))
        #expect(r.net == dec("464.5"))
    }

    @Test func transfersAreNeitherIncomeNorExpenseButFeesAre() {
        let t = EntryValue(kind: .transfer, amount: 200, currency: "CNY", date: day(2025, 3, 3), accountID: cashID,
                           toAccountID: savingsID, fee: 2, feeCategoryID: fees)
        let b = engine.balances(accounts: accounts, entries: [t])
        #expect(b[cashID] == 798)       // 1000 − 200 − 2
        #expect(b[savingsID] == 200)
        let r = engine.report([t], in: march)
        #expect(r.income == 0)
        #expect(r.expense == 2)
        #expect(r.fees == 2)
        #expect(engine.categoryShares([t], in: march, kind: .expense).first?.categoryID == fees)
    }

    @Test func creditCardSpendingAndRepaymentAreCountedOnce() {
        let spend = EntryValue(kind: .expense, amount: 300, currency: "CNY", date: day(2025, 3, 4), accountID: cardID, categoryID: food)
        let repay = EntryValue(kind: .transfer, amount: 300, currency: "CNY", date: day(2025, 3, 20), accountID: cashID, toAccountID: cardID)
        let entries = [spend, repay]
        let b = engine.balances(accounts: accounts, entries: entries)
        #expect(b[cardID] == 0)
        #expect(b[cashID] == 700)
        #expect(engine.report(entries, in: march).expense == 300)

        let afterSpend = engine.balances(accounts: accounts, entries: [spend])
        let worth = engine.netWorth(accounts: accounts, balances: afterSpend)
        #expect(worth.liabilities == 5_300)       // card 300 + loan 5000
        #expect(worth.assets.isSameAmount(as: 1_000 + 470))      // cash + AUD 100 × 4.70
        #expect(worth.net == worth.assets - 5_300)
    }

    @Test func refundsReduceCategorySpendingNotIncome() {
        let buy = EntryValue(kind: .expense, amount: 100, currency: "CNY", date: day(2025, 3, 5), accountID: cardID, categoryID: food)
        let refund = EntryValue(kind: .refund, amount: 40, currency: "CNY", date: day(2025, 3, 6), accountID: cardID, categoryID: food, refundOfID: buy.id)
        let r = engine.report([buy, refund], in: march)
        #expect(r.income == 0)
        #expect(r.expense == 60)
        #expect(r.refunds == 40)
        #expect(engine.categoryShares([buy, refund], in: march, kind: .expense).first?.amount == 60)
        #expect(engine.balances(accounts: accounts, entries: [buy, refund])[cardID] == -60)
    }

    @Test func splitsDriveCategoriesWhileBalanceMovesOnce() {
        let split = EntryValue(kind: .expense, amount: 100, currency: "CNY", date: day(2025, 3, 7), accountID: cashID,
                               splits: [SplitValue(categoryID: food, amount: 60), SplitValue(categoryID: pets, amount: 40)])
        #expect(engine.balances(accounts: accounts, entries: [split])[cashID] == 900)
        let shares = engine.categoryShares([split], in: march, kind: .expense)
        #expect(shares.map(\.amount) == [60, 40])
        #expect(shares.map(\.categoryID) == [food, pets])
    }

    @Test func splitConversionAddsUpExactlyAfterRounding() {
        // 10 AUD × 4.70 = 47.00 CNY split 1/3 each must still total 47.00.
        let split = EntryValue(kind: .expense, amount: 10, currency: "AUD", date: day(2025, 3, 8), accountID: audID,
                               splits: [SplitValue(categoryID: food, amount: dec("3.33")),
                                        SplitValue(categoryID: pets, amount: dec("3.33")),
                                        SplitValue(categoryID: fees, amount: dec("3.34"))])
        let parts = engine.expenseContributions(split)!
        #expect(parts.sum { $0.amount } == 47)
        #expect(FinanceEngine.allocate(10, across: [1, 1, 1], scale: 2) == [dec("3.33"), dec("3.33"), dec("3.34")])
    }

    @Test func missingRatesArePendingNeverOneToOne() {
        let usdAccount = AccountValue(id: UUID(), kind: .cash, currency: "USD", openingBalance: 50, openingDate: .distantPast, includeInNetWorth: true, isArchived: false)
        let e = EntryValue(kind: .expense, amount: 10, currency: "USD", date: day(2025, 3, 9), accountID: usdAccount.id, categoryID: food)
        let r = engine.report([e], in: march)
        #expect(r.expense == 0)
        #expect(r.pendingCount == 1)
        let worth = engine.netWorth(accounts: [usdAccount], balances: [usdAccount.id: 40])
        #expect(worth.assets == 0)
        #expect(worth.pendingAccountIDs == [usdAccount.id])
    }

    @Test func savedSnapshotWinsOverLaterRates() {
        let snap = RateSnapshot(base: "CNY", rate: dec("4.5"), baseAmount: 45)
        let e = EntryValue(kind: .expense, amount: 10, currency: "AUD", date: day(2025, 3, 10), accountID: audID, categoryID: food, snapshot: snap)
        #expect(engine.baseValue(e) == 45)
        // In another base currency the historical rate table is used instead.
        let audEngine = FinanceEngine(base: "AUD", rates: rates)
        #expect(audEngine.baseValue(e) == 10)
    }

    @Test func adjustmentsChangeBalanceOnlyAndRespectOpeningDate() {
        let opening = day(2025, 3, 10, 0)
        let acct = AccountValue(id: UUID(), kind: .cash, currency: "CNY", openingBalance: 100, openingDate: opening, includeInNetWorth: true, isArchived: false)
        let before = EntryValue(kind: .expense, amount: 30, currency: "CNY", date: day(2025, 3, 9), accountID: acct.id, categoryID: food)
        let adjust = EntryValue(kind: .adjustment, amount: 5, currency: "CNY", date: day(2025, 3, 11), accountID: acct.id, adjustmentDelta: -5)
        let b = engine.balances(accounts: [acct], entries: [before, adjust])
        #expect(b[acct.id] == 95)                          // earlier entry already in the opening balance
        let r = engine.report([before, adjust], in: march)
        #expect(r.expense == 30)                           // still part of March spending
        #expect(r.count == 2)
    }

    @Test func dailyAndMonthlySeriesSumToReport() {
        let entries = (1...20).map {
            EntryValue(kind: .expense, amount: Decimal($0), currency: "CNY", date: day(2025, 3, $0), accountID: cashID, categoryID: food)
        }
        let daily = engine.dailyExpense(entries, in: march)
        #expect(daily.count == 31)
        #expect(daily.sum { $0.amount } == 210)
        let months = engine.monthly(entries, months: [march.previous, march])
        #expect(months.map(\.expense) == [0, 210])
    }
}

struct BudgetEngineTests {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.ledger.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private let food = UUID(), rent = UUID(), cashID = UUID()
    private var finance: FinanceEngine { FinanceEngine(base: "CNY", rates: []) }

    private func spend(_ amount: Decimal, _ date: Date, _ category: UUID) -> EntryValue {
        EntryValue(kind: .expense, amount: amount, currency: "CNY", date: date, accountID: cashID, categoryID: category)
    }

    @Test func monthlyPeriodHonoursStartDay() {
        let engine = BudgetEngine(finance: finance, monthStartDay: 15)
        let budget = BudgetValue(amount: 100, currency: "CNY")
        let p = engine.period(of: budget, containing: day(2025, 3, 10))
        #expect(Calendar.ledger.component(.day, from: p.start) == 15)
        #expect(Calendar.ledger.component(.month, from: p.start) == 2)
        #expect(Calendar.ledger.component(.month, from: p.end) == 3)
    }

    @Test func overallBudgetExcludesCategoriesAndCountsRefunds() {
        let engine = BudgetEngine(finance: finance)
        let budget = BudgetValue(amount: 1_000, currency: "CNY", excluded: [rent])
        let refund = EntryValue(kind: .refund, amount: 50, currency: "CNY", date: day(2025, 3, 6), accountID: cashID, categoryID: food)
        let entries = [spend(4_000, day(2025, 3, 1), rent), spend(300, day(2025, 3, 5), food), refund]
        let status = engine.status(of: budget, entries: entries, at: day(2025, 3, 20))
        #expect(status.spent == 250)
        #expect(status.remaining == 750)
        #expect(status.level == .normal)
    }

    @Test func categoryAndOverallBudgetsAreViewsNotSums() {
        let engine = BudgetEngine(finance: finance)
        let entries = [spend(900, day(2025, 3, 5), food)]
        let overall = engine.status(of: BudgetValue(amount: 1_000, currency: "CNY", threshold: 0.8), entries: entries, at: day(2025, 3, 20))
        let category = engine.status(of: BudgetValue(amount: 800, currency: "CNY", categoryID: food), entries: entries, at: day(2025, 3, 20))
        #expect(overall.spent == 900)
        #expect(category.spent == 900)
        #expect(overall.level == .approaching)
        #expect(category.level == .exceeded)
        #expect(category.overspent == 100)
        #expect(category.dailyAllowance == nil)
    }

    @Test func rolloverCarriesLeftoverAndOverspending() {
        let engine = BudgetEngine(finance: finance)
        let budget = BudgetValue(amount: 1_000, currency: "CNY", rollover: true, createdAt: day(2025, 1, 2))
        let entries = [spend(600, day(2025, 1, 10), food), spend(1_300, day(2025, 2, 10), food), spend(100, day(2025, 3, 3), food)]
        let status = engine.status(of: budget, entries: entries, at: day(2025, 3, 15))
        // Jan leftover 400; Feb limit 1400 − 1300 = 100 carried into March.
        #expect(status.carried == 100)
        #expect(status.limit == 1_100)
        #expect(status.remaining == 1_000)
    }

    @Test func budgetInOtherCurrencyIsConvertedOrPending() {
        let budget = BudgetValue(amount: 100, currency: "AUD")
        let withRate = BudgetEngine(finance: FinanceEngine(base: "CNY", rates: [RatePoint(base: "AUD", quote: "CNY", rate: 5, date: day(2025, 1, 1))]))
        #expect(withRate.status(of: budget, entries: [], at: day(2025, 3, 1)).limit == 500)
        let without = BudgetEngine(finance: finance)
        #expect(without.status(of: budget, entries: [], at: day(2025, 3, 1)).limitPending)
    }
}

struct RecurrenceTests {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.ledger.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    @Test func monthEndsDoNotDrift() {
        let start = day(2025, 1, 31)
        let dates = (0..<3).map { Recurrence.occurrence($0, start: start, frequency: .monthly, interval: 1) }
        let days = dates.map { Calendar.ledger.component(.day, from: $0) }
        #expect(days == [31, 28, 31])
    }

    @Test func onlyDueOccurrencesAreReturned() {
        let due = Recurrence.dueOccurrences(start: day(2025, 1, 1), frequency: .weekly, interval: 2, fromIndex: 0, end: nil, now: day(2025, 2, 1))
        #expect(due.count == 3)    // Jan 1, Jan 15, Jan 29
        let later = Recurrence.dueOccurrences(start: day(2025, 1, 1), frequency: .weekly, interval: 2, fromIndex: 3, end: nil, now: day(2025, 2, 1))
        #expect(later.isEmpty)
    }
}
