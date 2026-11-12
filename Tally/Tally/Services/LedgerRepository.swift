import Foundation
import SwiftData

enum LedgerError: LocalizedError, Equatable {
    case amountMustBePositive
    case accountRequired
    case destinationRequired
    case sameAccountTransfer
    case splitTotalMismatch
    case splitNeedsCategory
    case nameRequired
    case invalidFee
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .amountMustBePositive: String(localized: "Enter an amount greater than zero.")
        case .accountRequired: String(localized: "Choose an account.")
        case .destinationRequired: String(localized: "Choose the account to transfer to.")
        case .sameAccountTransfer: String(localized: "Choose two different accounts.")
        case .splitTotalMismatch: String(localized: "Split amounts must add up to the total.")
        case .splitNeedsCategory: String(localized: "Choose a category for every split.")
        case .nameRequired: String(localized: "Enter a name.")
        case .invalidFee: String(localized: "The fee can't be negative.")
        case .saveFailed(let message): message
        }
    }
}

/// Data access for the ledger. Every multi-object change is committed with a
/// single `save()`, so a transfer, its fee and its splits are written atomically.
@MainActor
struct LedgerRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Reading

    func all<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    func rates() -> [ExchangeRate] { all(ExchangeRate.self) }

    func converter() -> CurrencyConverter { CurrencyConverter(rates: rates()) }

    func snapshot() -> LedgerSnapshot { LedgerSnapshot.load(from: context) }

    func account(id: UUID?) -> Account? {
        guard let id else { return nil }
        return all(Account.self).first { $0.id == id }
    }

    func category(id: UUID?) -> LedgerCategory? {
        guard let id else { return nil }
        return all(LedgerCategory.self).first { $0.id == id }
    }

    func entry(id: UUID?) -> LedgerEntry? {
        guard let id else { return nil }
        return all(LedgerEntry.self).first { $0.id == id }
    }

    // MARK: Writing

    /// Commits pending changes; rolls back on failure so no half-written state remains.
    func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw LedgerError.saveFailed(error.localizedDescription)
        }
    }

    func audit(_ action: String, _ entityKind: String, id: UUID?, _ summary: String) {
        context.insert(AuditRecord(action: action, entityKind: entityKind, entityID: id, summary: summary))
    }

    // MARK: Accounts

    func nextAccountSortOrder() -> Int {
        (all(Account.self).map(\.sortOrder).max() ?? -1) + 1
    }

    /// Deletes an account together with every entry that touches it.
    func deleteAccount(_ account: Account) throws {
        let id = account.id
        var removed = 0
        for e in all(LedgerEntry.self) where e.account?.id == id || e.toAccount?.id == id {
            context.delete(e)
            removed += 1
        }
        if AppSettings.uuid(forKey: SettingsKey.defaultAccountID) == id {
            AppSettings.setUUID(nil, forKey: SettingsKey.defaultAccountID)
        }
        audit(AuditRecord.Action.delete, "account", id: id, "\(account.name) · \(removed)")
        context.delete(account)
        try commit()
    }

    // MARK: Categories

    func nextCategorySortOrder(kind: CategoryKind) -> Int {
        (all(LedgerCategory.self).filter { $0.kind == kind }.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Deletes a category, optionally moving its entries and splits to another category first.
    func deleteCategory(_ category: LedgerCategory, reassignTo replacement: LedgerCategory?) throws {
        let id = category.id
        for e in all(LedgerEntry.self) where e.category?.id == id { e.category = replacement }
        for s in all(TransactionSplit.self) where s.category?.id == id { s.category = replacement }
        audit(AuditRecord.Action.delete, "category", id: id, category.name)
        context.delete(category)
        try commit()
    }

    /// The built-in category used for transfer fees.
    func feeCategory() -> LedgerCategory {
        let variants = L10n.variants(of: DefaultData.feeCategoryKey)
        if let existing = all(LedgerCategory.self).first(where: { $0.kind == .expense && variants.contains($0.name) }) {
            return existing
        }
        let c = LedgerCategory(
            name: L10n.current(DefaultData.feeCategoryKey),
            kind: .expense,
            symbolName: "percent",
            colorHex: "7D8BA6",
            sortOrder: nextCategorySortOrder(kind: .expense)
        )
        context.insert(c)
        return c
    }

    // MARK: Tags

    func findOrCreateTag(named raw: String) -> Tag? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let tags = all(Tag.self)
        if let existing = tags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let tag = Tag(name: name, colorHex: DS.Palette.swatches[tags.count % DS.Palette.swatches.count])
        context.insert(tag)
        try? commit()
        return tag
    }

    // MARK: Budgets

    struct BudgetDraft {
        var amount: Decimal
        /// Currency the limit is set in; converted to the base currency at today's rate.
        var currencyCode: String = AppSettings.baseCurrency
        var category: LedgerCategory?
        var threshold: Double = 0.8
        var period: BudgetPeriodKind = .monthly
        var customLengthDays: Int = 30
        var anchorDate: Date = .now
        var rollover: Bool = false
        var excluded: Set<UUID> = []
    }

    @discardableResult
    func saveBudget(_ draft: BudgetDraft, editing: Budget?) throws -> Budget {
        guard draft.amount > 0 else { throw LedgerError.amountMustBePositive }
        let budget: Budget
        if let editing {
            budget = editing
        } else {
            budget = Budget(amount: draft.amount, currencyCode: draft.currencyCode, alertThreshold: draft.threshold)
            context.insert(budget)
        }
        budget.amount = draft.amount
        budget.currencyCode = draft.currencyCode
        budget.category = draft.category
        budget.alertThreshold = draft.threshold
        budget.periodKind = draft.period
        budget.customLengthDays = max(1, draft.customLengthDays)
        budget.anchorDate = Calendar.ledger.startOfDay(for: draft.anchorDate)
        budget.rollover = draft.rollover
        budget.excludedCategoryIDs = draft.category == nil ? draft.excluded : []
        audit(editing == nil ? AuditRecord.Action.create : AuditRecord.Action.update, "budget", id: budget.id,
              "\(DecimalCodec.encode(draft.amount)) \(draft.currencyCode) · \(draft.category?.name ?? "overall") · \(draft.period.rawValue)")
        try commit()
        return budget
    }

    func deleteBudget(_ budget: Budget) throws {
        audit(AuditRecord.Action.delete, "budget", id: budget.id,
              "\(DecimalCodec.encode(budget.amount)) \(budget.currencyCode) · \(budget.category?.name ?? "overall")")
        context.delete(budget)
        try commit()
    }

    // MARK: Rates

    func addRate(base: String, quote: String, rate: Decimal, date: Date, source: String = ExchangeRate.Source.manual,
                 ledgerBase: String = AppSettings.baseCurrency) throws {
        let day = Calendar.ledger.startOfDay(for: date)
        if let same = rates().first(where: {
            $0.baseCode == base && $0.quoteCode == quote && Calendar.ledger.isDate($0.effectiveDate, inSameDayAs: day)
                && $0.source != ExchangeRate.Source.reference
        }) {
            same.rate = rate
            same.source = source
        } else {
            context.insert(ExchangeRate(baseCode: base, quoteCode: quote, rate: rate, effectiveDate: day, source: source))
        }
        try commit()
        TransactionService(repository: self).refreshPendingSnapshots(base: ledgerBase)
    }

    // MARK: Bulk

    func deleteDemoData() throws {
        func remove<T: PersistentModel>(_ type: T.Type, where isDemo: (T) -> Bool) {
            for item in all(type) where isDemo(item) { context.delete(item) }
        }
        remove(LedgerEntry.self) { $0.isDemo }
        remove(Budget.self) { $0.isDemo }
        remove(Tag.self) { $0.isDemo }
        remove(RecurringRule.self) { $0.isDemo }
        remove(ExchangeRate.self) { $0.isDemo }
        try commit()
        for a in all(Account.self) where a.isDemo { try deleteAccount(a) }
        try commit()
    }

    func eraseAllData(reseed: Bool = true) throws {
        func wipe<T: PersistentModel>(_ type: T.Type) {
            for item in all(type) { context.delete(item) }
        }
        wipe(TransactionSplit.self)
        wipe(LedgerEntry.self)
        wipe(Budget.self)
        wipe(Tag.self)
        wipe(RecurringRule.self)
        try commit()
        wipe(Account.self)
        wipe(LedgerCategory.self)
        wipe(ExchangeRate.self)
        wipe(AuditRecord.self)
        try commit()
        for key in [SettingsKey.defaultAccountID, SettingsKey.lastExpenseCategoryID, SettingsKey.lastIncomeCategoryID, SettingsKey.budgetNotified] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        if reseed { DefaultData.ensureSeeded(in: context) }
    }

    var hasDemoData: Bool { all(Account.self).contains { $0.isDemo } }
}
