import Foundation
import SwiftData

// Immutable, Sendable copies of the ledger used by FinanceEngine. Views and
// services never compute money from the SwiftData objects directly; they build
// a snapshot (cheap, main actor) and run calculations on it (any thread).

struct AccountValue: Sendable, Identifiable, Hashable {
    let id: UUID
    let kind: AccountKind
    let currency: String
    let openingBalance: Decimal
    let openingDate: Date
    let includeInNetWorth: Bool
    let isArchived: Bool
}

struct SplitValue: Sendable, Hashable {
    let categoryID: UUID?
    let amount: Decimal
}

struct RateSnapshot: Sendable, Hashable {
    let base: String
    let rate: Decimal
    let baseAmount: Decimal
}

struct EntryValue: Sendable, Identifiable, Hashable {
    let id: UUID
    let kind: TransactionKind
    /// Positive amount in `currency` (the source account's currency).
    let amount: Decimal
    let currency: String
    let date: Date
    let accountID: UUID?
    let toAccountID: UUID?
    /// Amount credited to `toAccountID` (destination currency) for transfers.
    let toAmount: Decimal
    let fee: Decimal
    let feeCategoryID: UUID?
    let categoryID: UUID?
    let splits: [SplitValue]
    let tagIDs: [UUID]
    /// Signed balance change for adjustments.
    let adjustmentDelta: Decimal
    let snapshot: RateSnapshot?
    let refundOfID: UUID?

    init(
        id: UUID = UUID(),
        kind: TransactionKind,
        amount: Decimal,
        currency: String,
        date: Date,
        accountID: UUID?,
        toAccountID: UUID? = nil,
        toAmount: Decimal? = nil,
        fee: Decimal = 0,
        feeCategoryID: UUID? = nil,
        categoryID: UUID? = nil,
        splits: [SplitValue] = [],
        tagIDs: [UUID] = [],
        adjustmentDelta: Decimal = 0,
        snapshot: RateSnapshot? = nil,
        refundOfID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.date = date
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.toAmount = toAmount ?? amount
        self.fee = fee
        self.feeCategoryID = feeCategoryID
        self.categoryID = categoryID
        self.splits = splits
        self.tagIDs = tagIDs
        self.adjustmentDelta = adjustmentDelta
        self.snapshot = snapshot
        self.refundOfID = refundOfID
    }
}

struct BudgetValue: Sendable, Identifiable, Hashable {
    let id: UUID
    let amount: Decimal
    let currency: String
    let categoryID: UUID?
    let threshold: Double
    let period: BudgetPeriodKind
    let customLengthDays: Int
    let anchorDate: Date
    let rollover: Bool
    let excluded: Set<UUID>
    let createdAt: Date

    init(
        id: UUID = UUID(),
        amount: Decimal,
        currency: String,
        categoryID: UUID? = nil,
        threshold: Double = 0.8,
        period: BudgetPeriodKind = .monthly,
        customLengthDays: Int = 30,
        anchorDate: Date = .now,
        rollover: Bool = false,
        excluded: Set<UUID> = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.categoryID = categoryID
        self.threshold = threshold
        self.period = period
        self.customLengthDays = customLengthDays
        self.anchorDate = anchorDate
        self.rollover = rollover
        self.excluded = excluded
        self.createdAt = createdAt
    }
}

struct LedgerSnapshot: Sendable {
    var accounts: [AccountValue] = []
    /// Newest first.
    var entries: [EntryValue] = []
    var budgets: [BudgetValue] = []
    var rates: [RatePoint] = []

    var converter: CurrencyConverter { CurrencyConverter(points: rates) }
}

// MARK: - Building snapshots from SwiftData

extension AccountValue {
    init(_ a: Account) {
        self.init(
            id: a.id,
            kind: a.kind,
            currency: a.currencyCode,
            openingBalance: a.openingBalance,
            openingDate: a.openingDate,
            includeInNetWorth: a.includeInTotal,
            isArchived: a.isArchived
        )
    }
}

extension EntryValue {
    init(_ e: LedgerEntry) {
        let snapshot: RateSnapshot? = e.hasSnapshot
            ? RateSnapshot(base: e.baseCurrencyCode, rate: e.rateToBase, baseAmount: e.baseAmount)
            : nil
        self.init(
            id: e.id,
            kind: e.kind,
            amount: e.amount,
            currency: e.currencyCode,
            date: e.date,
            accountID: e.account?.id,
            toAccountID: e.toAccount?.id,
            toAmount: e.toAmountRaw.isEmpty ? nil : e.toAmount,
            fee: e.fee,
            feeCategoryID: UUID(uuidString: e.feeCategoryIDRaw),
            categoryID: e.category?.id,
            splits: e.splitList.map { SplitValue(categoryID: $0.category?.id, amount: $0.amount) },
            tagIDs: (e.tags ?? []).map(\.id),
            adjustmentDelta: e.kind == .adjustment ? e.adjustmentDelta : 0,
            snapshot: snapshot,
            refundOfID: UUID(uuidString: e.refundOfIDRaw)
        )
    }
}

extension BudgetValue {
    init(_ b: Budget) {
        self.init(
            id: b.id,
            amount: b.amount,
            currency: b.currencyCode,
            categoryID: b.category?.id,
            threshold: b.alertThreshold,
            period: b.periodKind,
            customLengthDays: b.customLengthDays,
            anchorDate: b.anchorDate,
            rollover: b.rollover,
            excluded: b.excludedCategoryIDs,
            createdAt: b.createdAt
        )
    }
}

extension LedgerSnapshot {
    /// Reads the whole ledger from the context. Must run on the context's actor.
    @MainActor
    static func load(from context: ModelContext) -> LedgerSnapshot {
        var s = LedgerSnapshot()
        s.accounts = ((try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []).map(AccountValue.init)
        s.entries = ((try? context.fetch(FetchDescriptor<LedgerEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []).map(EntryValue.init)
        s.budgets = ((try? context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []).map(BudgetValue.init)
        s.rates = ((try? context.fetch(FetchDescriptor<ExchangeRate>())) ?? []).map {
            RatePoint(base: $0.baseCode, quote: $0.quoteCode, rate: $0.rate, date: $0.effectiveDate)
        }
        return s
    }
}
