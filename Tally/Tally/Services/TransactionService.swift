import Foundation
import SwiftData

struct SplitDraft: Identifiable, Equatable {
    let id = UUID()
    var category: LedgerCategory?
    var amount: Decimal
    var note: String = ""

    static func == (lhs: SplitDraft, rhs: SplitDraft) -> Bool {
        lhs.id == rhs.id && lhs.category?.id == rhs.category?.id && lhs.amount.isSameAmount(as: rhs.amount) && lhs.note == rhs.note
    }
}

/// Everything needed to record or edit one ledger entry.
struct TransactionDraft {
    var kind: TransactionKind
    var amount: Decimal
    var date: Date
    var note: String = ""
    var payee: String = ""
    var account: Account?
    var toAccount: Account?
    /// Credited amount for cross-currency transfers (nil = converted automatically).
    var toAmount: Decimal?
    var fee: Decimal = 0
    var category: LedgerCategory?
    var splits: [SplitDraft] = []
    var tags: [Tag] = []
    var refundOfID: UUID?
    /// Rate typed in by the user: 1 unit of the account currency = `manualRate` base currency.
    var manualRate: Decimal?
    /// Set when a recurring rule books this entry (de-duplication key with `occurrenceDate`).
    var recurringRuleID: UUID?
    var occurrenceDate: Date?
}

/// Business rules for writing entries (docs/FINANCE_RULES.md §2–3).
@MainActor
struct TransactionService {
    let repository: LedgerRepository

    init(repository: LedgerRepository) {
        self.repository = repository
    }

    init(context: ModelContext) {
        self.init(repository: LedgerRepository(context: context))
    }

    private var context: ModelContext { repository.context }

    // MARK: Validation

    func validate(_ d: TransactionDraft) throws {
        guard d.amount > 0 else { throw LedgerError.amountMustBePositive }
        guard let account = d.account else { throw LedgerError.accountRequired }
        guard d.fee >= 0 else { throw LedgerError.invalidFee }
        if d.kind == .transfer {
            guard let dest = d.toAccount else { throw LedgerError.destinationRequired }
            guard dest.id != account.id else { throw LedgerError.sameAccountTransfer }
        }
        if d.kind == .expense, !d.splits.isEmpty {
            let digits = account.currency.fractionDigits
            let total = d.splits.sum { $0.amount.rounded(scale: digits) }
            guard total.isSameAmount(as: d.amount.rounded(scale: digits)) else { throw LedgerError.splitTotalMismatch }
            guard d.splits.allSatisfy({ $0.category != nil && $0.amount > 0 }) else { throw LedgerError.splitNeedsCategory }
        }
    }

    // MARK: Saving

    /// Creates or updates an entry (with its splits) in one atomic save.
    @discardableResult
    func save(_ d: TransactionDraft, editing existing: LedgerEntry? = nil, baseCurrency: String = AppSettings.baseCurrency) throws -> LedgerEntry {
        try validate(d)
        guard let account = d.account else { throw LedgerError.accountRequired }
        let currency = account.currencyCode
        let digits = account.currency.fractionDigits
        let amount = d.amount.rounded(scale: digits)
        let splits = d.kind == .expense ? d.splits : []

        // Resolve the credited amount of a cross-currency transfer before touching the
        // store: without a typed amount or a rate it is unknown and must not be guessed.
        var credited: Decimal?
        if d.kind == .transfer, let dest = d.toAccount, dest.currencyCode != currency {
            guard let value = d.toAmount
                ?? repository.converter().convert(amount, from: currency, to: dest.currencyCode, on: d.date) else {
                throw LedgerError.saveFailed(String(localized: "Enter the amount received in \(dest.currencyCode), or add an exchange rate."))
            }
            credited = value.rounded(scale: dest.currency.fractionDigits)
        }

        let entry: LedgerEntry
        if let existing {
            entry = existing
        } else {
            entry = LedgerEntry(kind: d.kind, amount: amount, currencyCode: currency, date: d.date)
            context.insert(entry)
        }

        let needsSnapshot = existing == nil
            || d.manualRate != nil
            || !entry.amount.isSameAmount(as: amount)
            || entry.currencyCode != currency
            || !Calendar.ledger.isDate(entry.date, inSameDayAs: d.date)
            || entry.baseCurrencyCode != baseCurrency
            || !entry.hasSnapshot

        entry.kind = d.kind
        entry.amount = amount
        entry.currencyCode = currency
        entry.date = d.date
        entry.note = d.note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.payee = d.payee.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.account = account
        entry.tags = d.tags
        entry.refundOfIDRaw = d.kind == .refund ? (d.refundOfID?.uuidString ?? "") : ""
        entry.adjustmentDeltaRaw = ""
        entry.adjustmentPreviousBalanceRaw = ""
        if let rule = d.recurringRuleID {
            entry.recurringRuleIDRaw = rule.uuidString
            entry.occurrenceDate = d.occurrenceDate.map { Calendar.ledger.startOfDay(for: $0) }
        }

        // Replace splits.
        for old in entry.splits ?? [] { context.delete(old) }
        entry.splits = []

        switch d.kind {
        case .transfer:
            entry.category = nil
            entry.toAccount = d.toAccount
            entry.fee = d.fee.rounded(scale: digits)
            entry.feeCategoryIDRaw = d.fee > 0 ? repository.feeCategory().id.uuidString : ""
            if let credited {
                entry.toAmount = credited
            } else {
                entry.toAmountRaw = ""
            }
        case .expense, .income, .refund:
            entry.toAccount = nil
            entry.toAmountRaw = ""
            entry.feeRaw = ""
            entry.feeCategoryIDRaw = ""
            if splits.isEmpty {
                entry.category = d.category
            } else {
                entry.category = nil
                for (i, s) in splits.enumerated() {
                    let split = TransactionSplit(amount: s.amount.rounded(scale: digits), note: s.note, sortOrder: i)
                    context.insert(split)
                    split.category = s.category
                    split.entry = entry
                }
            }
        case .adjustment:
            break
        }

        if let rate = d.manualRate, rate > 0, currency != baseCurrency {
            upsertRate(base: currency, quote: baseCurrency, rate: rate, date: d.date)
        }
        if needsSnapshot {
            applySnapshot(to: entry, base: baseCurrency, converter: repository.converter(), manualRate: d.manualRate)
        }
        entry.updatedAt = .now
        if existing != nil {
            repository.audit(AuditRecord.Action.update, "entry", id: entry.id, summary(of: entry))
        }
        try repository.commit()
        return entry
    }

    /// Records which rate converted the entry into the base currency.
    /// Without an available rate the snapshot stays empty (pending) — never 1:1.
    func applySnapshot(to entry: LedgerEntry, base: String, converter: CurrencyConverter, manualRate: Decimal? = nil) {
        let rate: Decimal?
        if entry.currencyCode == base {
            rate = 1
        } else if let manualRate, manualRate > 0 {
            rate = manualRate
        } else {
            rate = converter.rate(from: entry.currencyCode, to: base, on: entry.date)
        }
        entry.baseCurrencyCode = base
        if let rate {
            entry.rateToBase = rate
            entry.baseAmount = (entry.amount * rate).rounded(scale: CurrencyInfo.info(for: base).fractionDigits)
        } else {
            entry.rateToBaseRaw = ""
            entry.baseAmountRaw = ""
        }
    }

    /// Fills in snapshots for entries that were saved while no rate was available.
    @discardableResult
    func refreshPendingSnapshots(base: String = AppSettings.baseCurrency) -> Int {
        let converter = repository.converter()
        var fixed = 0
        for e in repository.all(LedgerEntry.self) where !e.hasSnapshot && e.kind != .adjustment {
            applySnapshot(to: e, base: base, converter: converter)
            if e.hasSnapshot { fixed += 1 }
        }
        if fixed > 0 { try? repository.commit() }
        return fixed
    }

    private func upsertRate(base: String, quote: String, rate: Decimal, date: Date) {
        let day = Calendar.ledger.startOfDay(for: date)
        if let same = repository.rates().first(where: {
            $0.baseCode == base && $0.quoteCode == quote && Calendar.ledger.isDate($0.effectiveDate, inSameDayAs: day)
                && $0.source == ExchangeRate.Source.manual
        }) {
            same.rate = rate
        } else {
            context.insert(ExchangeRate(baseCode: base, quoteCode: quote, rate: rate, effectiveDate: day))
        }
    }

    // MARK: Balance adjustment

    /// Records the difference between the calculated and the actual balance as an
    /// adjustment entry (audit trail), and marks the account reconciled.
    @discardableResult
    func reconcile(_ account: Account, actualBalance: Decimal, currentBalance: Decimal, note: String = "", date: Date = .now) throws -> LedgerEntry? {
        let digits = account.currency.fractionDigits
        let actual = actualBalance.rounded(scale: digits)
        let delta = actual - currentBalance.rounded(scale: digits)
        account.markReconciled(actual, at: date)
        guard !delta.isZero else {
            try repository.commit()
            return nil
        }
        let entry = LedgerEntry(kind: .adjustment, amount: delta.magnitudeValue, currencyCode: account.currencyCode, date: date, note: note)
        context.insert(entry)
        entry.account = account
        entry.adjustmentDelta = delta
        entry.adjustmentPreviousBalanceRaw = DecimalCodec.encode(currentBalance)
        entry.baseCurrencyCode = AppSettings.baseCurrency
        repository.audit(AuditRecord.Action.adjust, "account", id: account.id,
                         "\(account.name): \(DecimalCodec.encode(currentBalance)) → \(DecimalCodec.encode(actual))")
        try repository.commit()
        return entry
    }

    // MARK: Delete / duplicate

    func delete(_ entries: [LedgerEntry]) throws {
        for e in entries {
            repository.audit(AuditRecord.Action.delete, "entry", id: e.id, summary(of: e))
            context.delete(e)
        }
        try repository.commit()
    }

    func delete(_ entry: LedgerEntry) throws { try delete([entry]) }

    @discardableResult
    func duplicate(_ entry: LedgerEntry, date: Date = .now) throws -> LedgerEntry {
        var d = draft(from: entry)
        d.date = date
        return try save(d)
    }

    func draft(from e: LedgerEntry) -> TransactionDraft {
        TransactionDraft(
            kind: e.kind,
            amount: e.amount,
            date: e.date,
            note: e.note,
            payee: e.payee,
            account: e.account,
            toAccount: e.toAccount,
            toAmount: e.toAmountRaw.isEmpty ? nil : e.toAmount,
            fee: e.fee,
            category: e.category,
            splits: e.splitList.map { SplitDraft(category: $0.category, amount: $0.amount, note: $0.note) },
            tags: e.tags ?? [],
            refundOfID: UUID(uuidString: e.refundOfIDRaw)
        )
    }

    private func summary(of e: LedgerEntry) -> String {
        "\(e.kind.rawValue) \(DecimalCodec.encode(e.amount)) \(e.currencyCode) · \(e.displayTitle) · \(e.date.formatted(.iso8601))"
    }
}

extension Account {
    func markReconciled(_ value: Decimal, at date: Date) {
        reconciledBalanceRaw = DecimalCodec.encode(value)
        reconciledAt = date
    }
}
