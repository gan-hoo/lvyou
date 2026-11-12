import Foundation
import SwiftData

/// Validated input for creating or updating an entry.
struct EntryInput {
    var kind: TransactionKind
    var amount: Decimal
    var date: Date
    var note: String
    var account: Account?
    var toAccount: Account?
    /// Destination amount for cross-currency transfers (nil = same as `amount`).
    var toAmount: Decimal?
    var category: LedgerCategory?
    var tags: [Tag]
}

enum LedgerError: LocalizedError, Equatable {
    case amountMustBePositive
    case accountRequired
    case destinationRequired
    case sameAccountTransfer
    case nameRequired

    var errorDescription: String? {
        switch self {
        case .amountMustBePositive: String(localized: "Enter an amount greater than zero.")
        case .accountRequired: String(localized: "Choose an account.")
        case .destinationRequired: String(localized: "Choose the account to transfer to.")
        case .sameAccountTransfer: String(localized: "Choose two different accounts.")
        case .nameRequired: String(localized: "Enter a name.")
        }
    }
}

/// All writes to the ledger go through here so validation and the
/// base-currency snapshot logic live in one place.
@MainActor
struct LedgerStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Rates

    func converter() -> CurrencyConverter {
        CurrencyConverter(rates: (try? context.fetch(FetchDescriptor<ExchangeRate>())) ?? [])
    }

    // MARK: Entries

    @discardableResult
    func save(_ input: EntryInput, editing existing: LedgerEntry? = nil, baseCurrency: String = AppSettings.baseCurrency) throws -> LedgerEntry {
        guard input.amount > 0 else { throw LedgerError.amountMustBePositive }
        guard let account = input.account else { throw LedgerError.accountRequired }
        if input.kind == .transfer {
            guard let dest = input.toAccount else { throw LedgerError.destinationRequired }
            guard dest.id != account.id else { throw LedgerError.sameAccountTransfer }
        }

        let currency = account.currencyCode
        let amount = input.amount.rounded(scale: CurrencyInfo.info(for: currency).fractionDigits)
        let entry: LedgerEntry
        if let existing {
            entry = existing
        } else {
            entry = LedgerEntry(kind: input.kind, amount: amount, currencyCode: currency, date: input.date)
            context.insert(entry)
        }

        let needsSnapshot = existing == nil
            || entry.amount != amount
            || entry.currencyCode != currency
            || !Calendar.current.isDate(entry.date, inSameDayAs: input.date)
            || entry.baseCurrencyCode != baseCurrency

        entry.kind = input.kind
        entry.amount = amount
        entry.currencyCode = currency
        entry.date = input.date
        entry.note = input.note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.account = account
        entry.tags = input.tags

        switch input.kind {
        case .transfer:
            entry.category = nil
            entry.toAccount = input.toAccount
            if let dest = input.toAccount, dest.currencyCode != currency {
                let credited = input.toAmount
                    ?? converter().convert(amount, from: currency, to: dest.currencyCode, on: input.date)
                    ?? amount
                entry.toAmount = credited.rounded(scale: dest.currency.fractionDigits)
            } else {
                entry.toAmountRaw = ""
            }
        case .expense, .income:
            entry.category = input.category
            entry.toAccount = nil
            entry.toAmountRaw = ""
        }

        if needsSnapshot {
            applySnapshot(to: entry, base: baseCurrency, converter: converter())
        }
        entry.updatedAt = .now
        try context.save()
        return entry
    }

    /// Records which rate converted the entry into the base currency.
    func applySnapshot(to entry: LedgerEntry, base: String, converter: CurrencyConverter) {
        let rate = converter.rate(from: entry.currencyCode, to: base, on: entry.date) ?? 1
        entry.baseCurrencyCode = base
        entry.rateToBase = rate
        entry.baseAmount = (entry.amount * rate).rounded(scale: CurrencyInfo.info(for: base).fractionDigits)
    }

    func delete(_ entry: LedgerEntry) {
        context.delete(entry)
        try? context.save()
    }

    func delete(_ entries: [LedgerEntry]) {
        for e in entries { context.delete(e) }
        try? context.save()
    }

    @discardableResult
    func duplicate(_ entry: LedgerEntry, date: Date = .now) -> LedgerEntry? {
        let input = EntryInput(
            kind: entry.kind,
            amount: entry.amount,
            date: date,
            note: entry.note,
            account: entry.account,
            toAccount: entry.toAccount,
            toAmount: entry.toAmountRaw.isEmpty ? nil : entry.toAmount,
            category: entry.category,
            tags: entry.tags ?? []
        )
        return try? save(input)
    }

    // MARK: Accounts

    func nextAccountSortOrder() -> Int {
        let all = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        return (all.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Deletes an account together with every entry that touches it.
    func deleteAccount(_ account: Account) {
        let id = account.id
        let all = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        for e in all where e.account?.id == id || e.toAccount?.id == id {
            context.delete(e)
        }
        if AppSettings.uuid(forKey: SettingsKey.defaultAccountID) == id {
            AppSettings.setUUID(nil, forKey: SettingsKey.defaultAccountID)
        }
        context.delete(account)
        try? context.save()
    }

    // MARK: Categories

    func nextCategorySortOrder(kind: CategoryKind) -> Int {
        let raw = kind.rawValue
        let all = (try? context.fetch(FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.kindRaw == raw }))) ?? []
        return (all.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Deletes a category, optionally moving its entries to another category first.
    func deleteCategory(_ category: LedgerCategory, reassignTo replacement: LedgerCategory?) {
        let id = category.id
        let all = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        for e in all where e.category?.id == id {
            e.category = replacement
        }
        context.delete(category)
        try? context.save()
    }

    // MARK: Tags

    func findOrCreateTag(named raw: String) -> Tag? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let palette = DS.Palette.swatches
        let tag = Tag(name: name, colorHex: palette[all.count % palette.count])
        context.insert(tag)
        try? context.save()
        return tag
    }

    // MARK: Budgets

    func setBudget(amount: Decimal, category: LedgerCategory?, threshold: Double, editing: Budget?) {
        let base = AppSettings.baseCurrency
        if let editing {
            editing.amount = amount
            editing.currencyCode = base
            editing.category = category
            editing.alertThreshold = threshold
        } else {
            let budget = Budget(amount: amount, currencyCode: base, alertThreshold: threshold)
            context.insert(budget)
            budget.category = category
        }
        try? context.save()
    }

    // MARK: Rates

    func addRate(base: String, quote: String, rate: Decimal, date: Date, source: String = ExchangeRate.Source.manual) {
        let day = Calendar.current.startOfDay(for: date)
        let all = (try? context.fetch(FetchDescriptor<ExchangeRate>())) ?? []
        if let same = all.first(where: { $0.baseCode == base && $0.quoteCode == quote && Calendar.current.isDate($0.effectiveDate, inSameDayAs: day) && $0.source != ExchangeRate.Source.reference }) {
            same.rate = rate
            same.source = source
        } else {
            context.insert(ExchangeRate(baseCode: base, quoteCode: quote, rate: rate, effectiveDate: day, source: source))
        }
        try? context.save()
    }

    // MARK: Bulk

    func deleteDemoData() {
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.isDemo == true }))) ?? []
        entries.forEach { context.delete($0) }
        let budgets = (try? context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.isDemo == true }))) ?? []
        budgets.forEach { context.delete($0) }
        let tags = (try? context.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.isDemo == true }))) ?? []
        tags.forEach { context.delete($0) }
        try? context.save()
        let accounts = (try? context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.isDemo == true }))) ?? []
        for a in accounts { deleteAccount(a) }
        try? context.save()
    }

    func eraseAllData() {
        func wipe<T: PersistentModel>(_ type: T.Type) {
            let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
            for item in all { context.delete(item) }
        }
        wipe(LedgerEntry.self)
        wipe(Budget.self)
        wipe(Tag.self)
        try? context.save()
        wipe(Account.self)
        wipe(LedgerCategory.self)
        wipe(ExchangeRate.self)
        try? context.save()
        for key in [SettingsKey.defaultAccountID, SettingsKey.lastExpenseCategoryID, SettingsKey.lastIncomeCategoryID, SettingsKey.budgetNotified] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        DefaultData.ensureSeeded(in: context)
    }

    var hasDemoData: Bool {
        ((try? context.fetchCount(FetchDescriptor<Account>(predicate: #Predicate { $0.isDemo == true }))) ?? 0) > 0
    }
}
