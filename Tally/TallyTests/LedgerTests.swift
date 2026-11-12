import Foundation
import SwiftData
import Testing
@testable import Tally

/// Service-level tests against an in-memory SwiftData store.
@MainActor
struct LedgerServiceTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    var repo: LedgerRepository { LedgerRepository(context: context) }
    var service: TransactionService { TransactionService(repository: repo) }

    init() throws {
        container = try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }
    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        Calendar.ledger.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func category(_ name: String = "Food", kind: CategoryKind = .expense) -> LedgerCategory {
        let c = LedgerCategory(name: name, kind: kind, symbolName: "tag", colorHex: "8E8E93", sortOrder: 0)
        context.insert(c)
        return c
    }

    private func account(_ name: String, _ currency: String = "CNY", kind: AccountKind = .cash, opening: Decimal = 0) -> Account {
        let a = Account(name: name, kind: kind, currencyCode: currency, openingBalance: opening)
        context.insert(a)
        return a
    }

    private func balances() -> [UUID: Decimal] {
        let snap = repo.snapshot()
        return FinanceEngine(base: "CNY", rates: snap.rates).balances(accounts: snap.accounts, entries: snap.entries)
    }

    @Test func savesSplitAtomicallyAndValidatesTotals() throws {
        let cash = account("Cash", opening: 500)
        let food = category("Food"), pets = category("Pets")
        var d = TransactionDraft(kind: .expense, amount: 100, date: day(2025, 3, 1), account: cash)
        d.splits = [SplitDraft(category: food, amount: 70), SplitDraft(category: pets, amount: 20)]
        #expect(throws: LedgerError.splitTotalMismatch) { try service.save(d, baseCurrency: "CNY") }
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 0)

        d.splits[1].amount = 30
        let e = try service.save(d, baseCurrency: "CNY")
        #expect(e.splitList.count == 2)
        #expect(e.category == nil)
        #expect(balances()[cash.id] == 400)
    }

    @Test func rejectsInvalidDrafts() {
        let a = account("A")
        #expect(throws: LedgerError.amountMustBePositive) {
            try service.save(TransactionDraft(kind: .expense, amount: 0, date: .now, account: a), baseCurrency: "CNY")
        }
        #expect(throws: LedgerError.accountRequired) {
            try service.save(TransactionDraft(kind: .expense, amount: 5, date: .now, account: nil), baseCurrency: "CNY")
        }
        #expect(throws: LedgerError.sameAccountTransfer) {
            try service.save(TransactionDraft(kind: .transfer, amount: 5, date: .now, account: a, toAccount: a), baseCurrency: "CNY")
        }
    }

    @Test func crossCurrencyTransferNeedsRateOrTypedAmount() throws {
        let cny = account("CNY", opening: 1_000)
        let aud = account("AUD", "AUD")
        let draft = TransactionDraft(kind: .transfer, amount: 470, date: day(2025, 3, 1), account: cny, toAccount: aud)
        #expect(throws: (any Error).self) { try service.save(draft, baseCurrency: "CNY") }
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 0)

        var typed = draft
        typed.toAmount = dec("99.1")
        typed.fee = 3
        let t = try service.save(typed, baseCurrency: "CNY")
        #expect(t.toAmount == dec("99.1"))
        #expect(!t.feeCategoryIDRaw.isEmpty)
        let b = balances()
        #expect(b[cny.id] == 527)
        #expect(b[aud.id] == dec("99.1"))
    }

    @Test func snapshotUsesHistoricalRateManualRateOrStaysPending() throws {
        let usd = account("USD", "USD")
        let food = category()
        let pending = try service.save(TransactionDraft(kind: .expense, amount: 10, date: day(2025, 2, 1), account: usd, category: food), baseCurrency: "CNY")
        #expect(!pending.hasSnapshot)

        try repo.addRate(base: "USD", quote: "CNY", rate: 7, date: day(2025, 1, 1), ledgerBase: "CNY")
        #expect(pending.hasSnapshot)                 // filled in once a rate exists
        #expect(pending.baseAmount == 70)

        try repo.addRate(base: "USD", quote: "CNY", rate: dec("7.3"), date: day(2025, 1, 15), ledgerBase: "CNY")
        #expect(pending.baseAmount == 70)            // history never rewritten

        var draft = service.draft(from: pending)
        draft.note = "lunch"
        try service.save(draft, editing: pending, baseCurrency: "CNY")
        #expect(pending.baseAmount == 70)            // note-only edit keeps snapshot

        draft.amount = 20
        try service.save(draft, editing: pending, baseCurrency: "CNY")
        #expect(pending.rateToBase == dec("7.3"))
        #expect(pending.baseAmount == 146)

        var manual = TransactionDraft(kind: .expense, amount: 10, date: day(2025, 3, 1), account: usd, category: food)
        manual.manualRate = dec("7.25")
        let m = try service.save(manual, baseCurrency: "CNY")
        #expect(m.baseAmount == dec("72.5"))
    }

    @Test func refundLinksOriginalAndReducesSpending() throws {
        let card = account("Card", kind: .creditCard)
        let food = category()
        let buy = try service.save(TransactionDraft(kind: .expense, amount: 100, date: day(2025, 3, 1), account: card, category: food), baseCurrency: "CNY")
        var r = TransactionDraft(kind: .refund, amount: 30, date: day(2025, 3, 2), account: card, category: food)
        r.refundOfID = buy.id
        let refund = try service.save(r, baseCurrency: "CNY")
        #expect(refund.refundOfIDRaw == buy.id.uuidString)
        let snap = repo.snapshot()
        let report = FinanceEngine(base: "CNY", rates: []).report(snap.entries, in: .month(day(2025, 3, 10)))
        #expect(report.expense == 70)
        #expect(report.income == 0)
        #expect(balances()[card.id] == -70)
    }

    @Test func reconcileCreatesAuditedAdjustment() throws {
        let cash = account("Cash", opening: 100)
        let food = category()
        try service.save(TransactionDraft(kind: .expense, amount: 30, date: .now, account: cash, category: food), baseCurrency: "CNY")
        let adj = try service.reconcile(cash, actualBalance: 65, currentBalance: balances()[cash.id] ?? 0)
        #expect(adj?.adjustmentDelta == -5)
        #expect(balances()[cash.id] == 65)
        #expect(cash.reconciledBalance == 65)
        #expect(try context.fetch(FetchDescriptor<AuditRecord>()).contains { $0.action == AuditRecord.Action.adjust })
        // Already balanced: no extra entry.
        #expect(try service.reconcile(cash, actualBalance: 65, currentBalance: 65) == nil)
        let report = FinanceEngine(base: "CNY", rates: []).report(repo.snapshot().entries, in: .month())
        #expect(report.expense == 30)
    }

    @Test func editAndDeleteKeepBalancesConsistent() throws {
        let cash = account("Cash", opening: 100)
        let food = category()
        let e = try service.save(TransactionDraft(kind: .expense, amount: 30, date: .now, account: cash, category: food), baseCurrency: "CNY")
        var d = service.draft(from: e)
        d.amount = 45
        try service.save(d, editing: e, baseCurrency: "CNY")
        #expect(balances()[cash.id] == 55)
        let copy = try service.duplicate(e)
        #expect(balances()[cash.id] == 10)
        try service.delete([e, copy])
        #expect(balances()[cash.id] == 100)
        let audits = try context.fetch(FetchDescriptor<AuditRecord>())
        #expect(audits.filter { $0.action == AuditRecord.Action.delete }.count == 2)
        #expect(audits.contains { $0.action == AuditRecord.Action.update })
    }

    @Test func roundsToAccountCurrency() throws {
        let jpy = account("JPY", "JPY")
        let e = try service.save(TransactionDraft(kind: .expense, amount: dec("1234.6"), date: .now, account: jpy), baseCurrency: "JPY")
        #expect(e.amount == 1235)
    }

    @Test func deletingAccountRemovesItsEntries() throws {
        let a = account("A", opening: 100), b = account("B")
        try service.save(TransactionDraft(kind: .expense, amount: 5, date: .now, account: a), baseCurrency: "CNY")
        try service.save(TransactionDraft(kind: .transfer, amount: 5, date: .now, account: b, toAccount: a), baseCurrency: "CNY")
        try service.save(TransactionDraft(kind: .expense, amount: 7, date: .now, account: b), baseCurrency: "CNY")
        try repo.deleteAccount(a)
        let remaining = try context.fetch(FetchDescriptor<LedgerEntry>())
        #expect(remaining.map(\.amount) == [7])
    }

    @Test func recurringPostsDueOccurrencesOnce() throws {
        let cash = account("Cash", opening: 10_000)
        let rent = category("Rent")
        let rule = RecurringRule(name: "Rent", kind: .expense, amount: 1_000, frequency: .monthly, startDate: day(2025, 1, 1, 9))
        rule.accountID = cash.id
        rule.categoryID = rent.id
        context.insert(rule)
        try context.save()

        let recurring = RecurringService(context: context)
        let first = recurring.postDueOccurrences(now: day(2025, 3, 15))
        #expect(first.posted == 3)
        let again = recurring.postDueOccurrences(now: day(2025, 3, 15))
        #expect(again.posted == 0)
        #expect(balances()[cash.id] == 7_000)
        #expect(Calendar.ledger.component(.month, from: rule.nextDate) == 4)

        // Even if the counter were lost, the occurrence key prevents double booking.
        rule.generatedCount = 0
        let replay = recurring.postDueOccurrences(now: day(2025, 3, 15))
        #expect(replay.posted == 0)
        #expect(replay.skippedDuplicates == 3)
    }

    @Test func backupRoundTripsAndDetectsTampering() throws {
        let cash = account("Cash", opening: 50)
        let food = category(), pets = category("Pets")
        var d = TransactionDraft(kind: .expense, amount: 10, date: day(2025, 3, 1), account: cash)
        d.splits = [SplitDraft(category: food, amount: 6), SplitDraft(category: pets, amount: 4)]
        try service.save(d, baseCurrency: "CNY")

        let data = try BackupService(context: context).exportData()
        let file = try BackupService.read(data)
        #expect(file.payload.entries.count == 1)

        let other = try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let summary = try BackupService(context: other.mainContext).restore(file, mode: .merge)
        #expect(summary.added >= 4)
        let restored = try other.mainContext.fetch(FetchDescriptor<LedgerEntry>())
        #expect(restored.first?.splitList.map(\.amount) == [6, 4])
        let again = try BackupService(context: other.mainContext).restore(file, mode: .merge)
        #expect(again.added == 0)

        var json = String(decoding: data, as: UTF8.self)
        json = json.replacingOccurrences(of: "\"Cash\"", with: "\"Kash\"")
        #expect(throws: (any Error).self) { try BackupService.read(Data(json.utf8)) }
    }

    @Test func integrityCheckFindsAndRepairsPendingRates() throws {
        let usd = account("USD", "USD")
        try service.save(TransactionDraft(kind: .expense, amount: 10, date: day(2025, 2, 1), account: usd), baseCurrency: "CNY")
        let integrity = IntegrityService(context: context)
        #expect(integrity.run(base: "CNY").issues.map(\.kind) == [.pendingConversion])
        context.insert(ExchangeRate(baseCode: "USD", quoteCode: "CNY", rate: 7, effectiveDate: day(2025, 1, 1)))
        try context.save()
        #expect(integrity.repair(base: "CNY") == 1)
        #expect(integrity.run(base: "CNY").isHealthy)
    }

    @Test func demoDataIsFlaggedAndRemovable() throws {
        DefaultData.ensureSeeded(in: context)
        let mine = account("Mine")
        try service.save(TransactionDraft(kind: .expense, amount: 1, date: .now, account: mine), baseCurrency: "CNY")

        DemoData.load(into: context, base: "CNY")
        let all = try context.fetch(FetchDescriptor<LedgerEntry>())
        #expect(all.count > 100)
        #expect(all.filter { !$0.isDemo }.count == 1)
        #expect(all.allSatisfy { $0.date <= .now })
        #expect(all.contains { $0.isSplit })
        #expect(all.contains { $0.kind == .refund })

        try repo.deleteDemoData()
        #expect(try context.fetch(FetchDescriptor<LedgerEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Account>()).map(\.name) == ["Mine"])
        #expect(try context.fetchCount(FetchDescriptor<Budget>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RecurringRule>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ExchangeRate>()) == 0)
    }
}

@MainActor
struct LocalizationTests {
    @Test func bundlesContainBothChineseScripts() {
        #expect(L10n.string("Dining", language: "zh-Hans") == "餐饮")
        #expect(L10n.string("Dining", language: "zh-Hant") == "餐飲")
        #expect(L10n.string("Dining", language: "en") == "Dining")
        #expect(L10n.variants(of: "Cash").isSuperset(of: ["Cash", "现金", "現金"]))
    }

    @Test func builtInNamesFollowTheRunningLanguage() throws {
        let container = try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let seeded = LedgerCategory(name: "餐饮", kind: .expense, symbolName: "fork.knife", colorHex: "F2994A", sortOrder: 0)
        let custom = LedgerCategory(name: "My Food", kind: .expense, symbolName: "fork.knife", colorHex: "F2994A", sortOrder: 1)
        let account = Account(name: "現金", kind: .cash, currencyCode: "CNY")
        context.insert(seeded); context.insert(custom); context.insert(account)

        DefaultData.relocalizeBuiltInNames(in: context)

        #expect(seeded.name == L10n.current("Dining"))
        #expect(account.name == L10n.current("Cash"))
        #expect(custom.name == "My Food")
    }
}
