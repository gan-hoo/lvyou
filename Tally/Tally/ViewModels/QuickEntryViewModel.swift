import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class QuickEntryViewModel {
    private(set) var kind: TransactionKind
    var expression: AmountExpression
    private(set) var account: Account?
    var toAccount: Account?
    /// Manually entered credited amount for cross-currency transfers ("" = automatic).
    var toAmountText: String = ""
    var category: LedgerCategory?
    var date: Date
    var note: String
    var tags: [Tag]
    var errorMessage: String?

    let editing: LedgerEntry?

    init(request: EntryRequest, accounts: [Account], categories: [LedgerCategory]) {
        let editing = request.editing
        let kind = editing?.kind ?? request.kind

        let active = accounts.filter { !$0.isArchived }
        let defaultID = AppSettings.uuid(forKey: SettingsKey.defaultAccountID)
        let source = editing?.account
            ?? request.account
            ?? active.first { $0.id == defaultID }
            ?? active.first
        let destination = editing?.toAccount ?? active.first { $0.id != source?.id }

        var toAmountText = ""
        if let editing, editing.kind == .transfer, !editing.toAmountRaw.isEmpty {
            toAmountText = DecimalCodec.encode(editing.toAmount)
        }

        let digits = CurrencyInfo.info(for: source?.currencyCode ?? AppSettings.baseCurrency).fractionDigits
        let expression = editing.map { AmountExpression(value: $0.amount, maxFractionDigits: digits) }
            ?? AmountExpression(maxFractionDigits: digits)

        let category: LedgerCategory?
        if let editing {
            category = editing.category
        } else if let preset = request.category {
            category = preset
        } else {
            category = Self.defaultCategory(for: kind, in: categories)
        }

        self.editing = editing
        self.kind = kind
        self.expression = expression
        self.account = source
        self.toAccount = destination
        self.toAmountText = toAmountText
        self.category = category
        self.date = editing?.date ?? request.date ?? .now
        self.note = editing?.note ?? ""
        self.tags = editing?.tags ?? []
        self.errorMessage = nil
    }

    // MARK: Derived

    var currencyCode: String { account?.currencyCode ?? AppSettings.baseCurrency }

    var amount: Decimal { expression.value }

    var isCrossCurrencyTransfer: Bool {
        kind == .transfer && toAccount != nil && toAccount?.currencyCode != account?.currencyCode
    }

    var canSave: Bool {
        guard amount > 0, account != nil else { return false }
        if kind == .transfer {
            return toAccount != nil && toAccount?.id != account?.id
        }
        return true
    }

    var isEditing: Bool { editing != nil }

    // MARK: Mutations

    func setKind(_ newKind: TransactionKind, categories: [LedgerCategory]) {
        guard newKind != kind else { return }
        kind = newKind
        if let catKind = newKind.categoryKind, category?.kind != catKind {
            category = Self.defaultCategory(for: newKind, in: categories)
        }
        if newKind == .transfer, toAccount?.id == account?.id {
            toAccount = nil
        }
        errorMessage = nil
    }

    func selectAccount(_ newAccount: Account) {
        account = newAccount
        let digits = newAccount.currency.fractionDigits
        if digits != expression.maxFractionDigits {
            let current = expression.value
            expression = AmountExpression(value: current, maxFractionDigits: digits)
        }
        if toAccount?.id == newAccount.id { toAccount = nil }
    }

    func swapTransferAccounts() {
        guard let from = account, let to = toAccount else { return }
        account = to
        toAccount = from
        toAmountText = ""
    }

    func toggle(_ tag: Tag) {
        if let i = tags.firstIndex(where: { $0.id == tag.id }) {
            tags.remove(at: i)
        } else {
            tags.append(tag)
        }
    }

    /// Automatic credited amount preview for cross-currency transfers.
    func estimatedToAmount(converter: CurrencyConverter) -> Decimal? {
        guard isCrossCurrencyTransfer, let dest = toAccount else { return nil }
        return converter.convert(amount, from: currencyCode, to: dest.currencyCode, on: date)
    }

    /// Saves and returns the stored entry, or sets `errorMessage`.
    func save(context: ModelContext) -> LedgerEntry? {
        if expression.hasPendingOperation { expression.collapse() }
        let store = LedgerStore(context: context)
        let manualToAmount = DecimalCodec.parseLenient(toAmountText).flatMap { $0 > 0 ? $0 : nil }
        let input = EntryInput(
            kind: kind,
            amount: amount,
            date: date,
            note: note,
            account: account,
            toAccount: kind == .transfer ? toAccount : nil,
            toAmount: isCrossCurrencyTransfer ? manualToAmount : nil,
            category: kind == .transfer ? nil : category,
            tags: tags
        )
        do {
            let entry = try store.save(input, editing: editing)
            rememberDefaults()
            errorMessage = nil
            return entry
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func rememberDefaults() {
        if let category, kind != .transfer {
            AppSettings.setUUID(category.id, forKey: kind == .expense ? SettingsKey.lastExpenseCategoryID : SettingsKey.lastIncomeCategoryID)
        }
    }

    static func defaultCategory(for kind: TransactionKind, in categories: [LedgerCategory]) -> LedgerCategory? {
        guard let catKind = kind.categoryKind else { return nil }
        let candidates = categories
            .filter { $0.kind == catKind && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
        let key = kind == .expense ? SettingsKey.lastExpenseCategoryID : SettingsKey.lastIncomeCategoryID
        if let last = AppSettings.uuid(forKey: key), let match = candidates.first(where: { $0.id == last }) {
            return match
        }
        return candidates.first
    }
}
