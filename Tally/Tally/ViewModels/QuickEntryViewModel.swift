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
    var toAmountText: String
    var feeText: String
    var category: LedgerCategory?
    var splits: [SplitDraft]
    var date: Date
    var note: String
    var payee: String
    var tags: [Tag]
    /// "" = use the stored rate for the date; otherwise 1 account currency = x base.
    var manualRateText: String
    var errorMessage: String?

    let editing: LedgerEntry?
    let refundOf: LedgerEntry?

    init(request: EntryRequest, accounts: [Account], categories: [LedgerCategory]) {
        let editing = request.editing
        let kind = editing?.kind ?? request.kind
        let active = accounts.filter { !$0.isArchived }
        let defaultID = AppSettings.uuid(forKey: SettingsKey.defaultAccountID)
        let destination = editing?.toAccount ?? request.toAccount
        let source = editing?.account
            ?? request.account
            ?? active.first { $0.id == defaultID && $0.id != destination?.id }
            ?? active.first { $0.id != destination?.id }
        let refundOf = request.refundOf

        let digits = CurrencyInfo.info(for: source?.currencyCode ?? AppSettings.baseCurrency).fractionDigits
        var expression = AmountExpression(maxFractionDigits: digits)
        if let editing {
            expression = AmountExpression(value: editing.amount, maxFractionDigits: digits)
        } else if let refundOf {
            expression = AmountExpression(value: refundOf.amount, maxFractionDigits: digits)
        }

        let category: LedgerCategory?
        if let editing {
            category = editing.category
        } else if let preset = request.category {
            category = preset
        } else {
            category = Self.defaultCategory(for: kind, in: categories)
        }

        self.editing = editing
        self.refundOf = refundOf
        self.kind = kind
        self.expression = expression
        self.account = source
        self.toAccount = destination ?? (kind == .transfer ? active.first { $0.id != source?.id } : nil)
        self.toAmountText = (editing?.kind == .transfer && !(editing?.toAmountRaw.isEmpty ?? true)) ? DecimalCodec.encode(editing!.toAmount) : ""
        self.feeText = (editing?.fee ?? 0) > 0 ? DecimalCodec.encode(editing!.fee) : ""
        self.category = category
        self.splits = editing?.splitList.map { SplitDraft(category: $0.category, amount: $0.amount, note: $0.note) } ?? []
        self.date = editing?.date ?? request.date ?? .now
        self.note = editing?.note ?? ""
        self.payee = editing?.payee ?? refundOf?.payee ?? ""
        self.tags = editing?.tags ?? []
        self.manualRateText = ""
        self.errorMessage = nil
        self.initialSignatureStorage = signature
    }

    @ObservationIgnored private var initialSignatureStorage = ""

    private var signature: String {
        [kind.rawValue, expression.expressionText, account?.id.uuidString ?? "", toAccount?.id.uuidString ?? "",
         toAmountText, feeText, category?.id.uuidString ?? "", "\(splits.count)", note, payee,
         "\(tags.count)", manualRateText, "\(date.timeIntervalSince1970)"].joined(separator: "|")
    }

    /// True once anything differs from how the sheet opened (protects against accidental dismissal).
    var hasChanges: Bool { signature != initialSignatureStorage }

    // MARK: Derived

    var currencyCode: String { account?.currencyCode ?? AppSettings.baseCurrency }
    var amount: Decimal { expression.value }

    /// Replaces the typed amount (e.g. with the sum of the split parts).
    func setAmount(_ value: Decimal) {
        expression = AmountExpression(value: value, maxFractionDigits: expression.maxFractionDigits)
    }
    var fee: Decimal { DecimalCodec.parseLenient(feeText)?.magnitudeValue ?? 0 }
    var manualRate: Decimal? { DecimalCodec.parseLenient(manualRateText).flatMap { $0 > 0 ? $0 : nil } }
    var isEditing: Bool { editing != nil }
    var isRefund: Bool { kind == .refund }
    var splitTotal: Decimal { splits.sum { $0.amount } }

    var isCrossCurrencyTransfer: Bool {
        kind == .transfer && toAccount != nil && toAccount?.currencyCode != account?.currencyCode
    }

    var canSave: Bool {
        guard amount > 0, account != nil else { return false }
        if kind == .transfer { return toAccount != nil && toAccount?.id != account?.id }
        if !splits.isEmpty { return splitTotal.isSameAmount(as: amount) }
        return true
    }

    // MARK: Mutations

    func setKind(_ newKind: TransactionKind, categories: [LedgerCategory]) {
        guard newKind != kind else { return }
        kind = newKind
        if let catKind = newKind.categoryKind, category?.kind != catKind {
            category = Self.defaultCategory(for: newKind, in: categories)
        }
        if newKind != .expense { splits = [] }
        if newKind == .transfer, toAccount == nil || toAccount?.id == account?.id {
            toAccount = nil
        }
        errorMessage = nil
    }

    func selectAccount(_ newAccount: Account) {
        account = newAccount
        let digits = newAccount.currency.fractionDigits
        if digits != expression.maxFractionDigits {
            expression = AmountExpression(value: expression.value, maxFractionDigits: digits)
        }
        if toAccount?.id == newAccount.id { toAccount = nil }
        manualRateText = ""
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

    func estimatedToAmount(converter: CurrencyConverter) -> Decimal? {
        guard isCrossCurrencyTransfer, let dest = toAccount else { return nil }
        return converter.convert(amount, from: currencyCode, to: dest.currencyCode, on: date)
    }

    /// Saves atomically and returns the stored entry, or sets `errorMessage`.
    func save(context: ModelContext) -> LedgerEntry? {
        if expression.hasPendingOperation { expression.collapse() }
        let service = TransactionService(context: context)
        var draft = TransactionDraft(kind: kind, amount: amount, date: date, note: note, payee: payee, account: account)
        draft.toAccount = kind == .transfer ? toAccount : nil
        draft.toAmount = isCrossCurrencyTransfer ? DecimalCodec.parseLenient(toAmountText).flatMap { $0 > 0 ? $0 : nil } : nil
        draft.fee = kind == .transfer ? fee : 0
        draft.category = kind == .transfer ? nil : (splits.isEmpty ? category : nil)
        draft.splits = kind == .expense ? splits : []
        draft.tags = tags
        draft.refundOfID = kind == .refund ? (refundOf?.id ?? UUID(uuidString: editing?.refundOfIDRaw ?? "")) : nil
        draft.manualRate = kind == .transfer ? nil : manualRate
        do {
            let entry = try service.save(draft, editing: editing)
            rememberDefaults()
            errorMessage = nil
            return entry
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func rememberDefaults() {
        if let category, kind == .expense || kind == .income {
            AppSettings.setUUID(category.id, forKey: kind == .expense ? SettingsKey.lastExpenseCategoryID : SettingsKey.lastIncomeCategoryID)
        }
    }

    static func defaultCategory(for kind: TransactionKind, in categories: [LedgerCategory]) -> LedgerCategory? {
        guard let catKind = kind.categoryKind else { return nil }
        let candidates = categories
            .filter { $0.kind == catKind && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
        let key = catKind == .expense ? SettingsKey.lastExpenseCategoryID : SettingsKey.lastIncomeCategoryID
        if let last = AppSettings.uuid(forKey: key), let match = candidates.first(where: { $0.id == last }) {
            return match
        }
        return candidates.first
    }
}
