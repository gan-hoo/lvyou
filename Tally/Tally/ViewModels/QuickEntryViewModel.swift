import Foundation
import SwiftData
import Observation

enum KeypadTarget: Hashable {
    case amount, discount, fee, rate, received
}

@Observable
@MainActor
final class QuickEntryViewModel {
    private(set) var kind: TransactionKind
    var expression: AmountExpression
    private(set) var account: Account?
    var toAccount: Account?
    /// Number fields typed on the app's keypad (never the system keyboard).
    /// Credited amount for cross-currency transfers (empty = automatic).
    var receivedInput: AmountExpression
    var feeInput: AmountExpression
    var discountInput: AmountExpression
    /// Empty = use the stored rate for the date; otherwise 1 account currency = x base.
    var rateInput: AmountExpression
    /// Which number the keypad is typing into.
    var keypadTarget: KeypadTarget = .amount
    var category: LedgerCategory?
    var splits: [SplitDraft]
    var date: Date
    var note: String
    var payee: String
    var tags: [Tag]
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
            // A refund returns what was paid for the goods: the price less any discount.
            expression = AmountExpression(value: refundOf.amount - refundOf.discount, maxFractionDigits: digits)
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
        let toDigits = (destination?.currency.fractionDigits) ?? 2
        let received = (editing?.kind == .transfer && !(editing?.toAmountRaw.isEmpty ?? true)) ? editing!.toAmount : 0
        self.receivedInput = Self.input(received, digits: toDigits)
        self.feeInput = Self.input(editing?.fee ?? 0, digits: digits)
        self.discountInput = Self.input(editing?.discount ?? 0, digits: digits)
        self.rateInput = AmountExpression(maxFractionDigits: Self.rateDigits)
        self.category = category
        self.splits = editing?.splitList.map { SplitDraft(category: $0.category, amount: $0.amount, note: $0.note) } ?? []
        self.date = editing?.date ?? request.date ?? .now
        self.note = editing?.note ?? ""
        self.payee = editing?.payee ?? refundOf?.payee ?? ""
        self.tags = editing?.tags ?? []
        self.errorMessage = nil
        self.initialSignatureStorage = signature
    }

    @ObservationIgnored private var initialSignatureStorage = ""

    static let rateDigits = 6

    private static func input(_ value: Decimal, digits: Int) -> AmountExpression {
        value > 0 ? AmountExpression(value: value, maxFractionDigits: digits) : AmountExpression(maxFractionDigits: digits)
    }

    // Text forms of the number fields (signature, tests and older call sites).
    var toAmountText: String {
        get { receivedInput.expressionText }
        set { receivedInput = Self.input(DecimalCodec.parseLenient(newValue) ?? 0, digits: receivedInput.maxFractionDigits) }
    }
    var feeText: String {
        get { feeInput.expressionText }
        set { feeInput = Self.input(DecimalCodec.parseLenient(newValue) ?? 0, digits: feeInput.maxFractionDigits) }
    }
    var discountText: String {
        get { discountInput.expressionText }
        set { discountInput = Self.input(DecimalCodec.parseLenient(newValue) ?? 0, digits: discountInput.maxFractionDigits) }
    }
    var manualRateText: String {
        get { rateInput.expressionText }
        set { rateInput = Self.input(DecimalCodec.parseLenient(newValue) ?? 0, digits: Self.rateDigits) }
    }

    // MARK: Keypad

    /// The number the keypad is currently editing.
    var activeInput: AmountExpression {
        get {
            switch keypadTarget {
            case .amount: expression
            case .discount: discountInput
            case .fee: feeInput
            case .rate: rateInput
            case .received: receivedInput
            }
        }
        set {
            switch keypadTarget {
            case .amount: expression = newValue
            case .discount: discountInput = newValue
            case .fee: feeInput = newValue
            case .rate: rateInput = newValue
            case .received: receivedInput = newValue
            }
        }
    }

    func focus(_ target: KeypadTarget) {
        if keypadTarget != target, activeInput.hasPendingOperation { activeInput.collapse() }
        keypadTarget = target
        if target == .received, let digits = toAccount?.currency.fractionDigits, receivedInput.maxFractionDigits != digits {
            receivedInput = Self.input(receivedInput.value, digits: digits)
        }
    }

    /// Applies a keypad key (other than Save) to the targeted number.
    func apply(_ key: KeypadKey) {
        switch key {
        case .digit(let n): activeInput.input(digit: n)
        case .decimal: activeInput.inputDecimalPoint()
        case .op(let op): activeInput.input(op)
        case .backspace: activeInput.backspace()
        case .clear: activeInput.clear()
        case .commit: if activeInput.hasPendingOperation { activeInput.collapse() }
        }
    }

    private var signature: String {
        [kind.rawValue, expression.expressionText, account?.id.uuidString ?? "", toAccount?.id.uuidString ?? "",
         toAmountText, feeText, discountText, category?.id.uuidString ?? "", "\(splits.count)", note, payee,
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
    var fee: Decimal { feeInput.value.magnitudeValue }
    var discount: Decimal { discountInput.value.magnitudeValue }
    /// Expense paid from the account: price − discount + fee.
    var paidAmount: Decimal { amount - discount + fee }
    var hasPriceAdjustments: Bool { kind == .expense && (discount > 0 || fee > 0) }
    var manualRate: Decimal? { rateInput.value > 0 ? rateInput.value : nil }
    /// Credited amount typed for a cross-currency transfer, if any.
    var typedReceived: Decimal? { receivedInput.value > 0 ? receivedInput.value : nil }
    var isEditing: Bool { editing != nil }
    var isRefund: Bool { kind == .refund }
    var splitTotal: Decimal { splits.sum { $0.amount } }

    var isCrossCurrencyTransfer: Bool {
        kind == .transfer && toAccount != nil && toAccount?.currencyCode != account?.currencyCode
    }

    var canSave: Bool {
        guard amount > 0, account != nil else { return false }
        if kind == .expense && discount > amount { return false }
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
        keypadTarget = .amount
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
            feeInput = Self.input(feeInput.value, digits: digits)
            discountInput = Self.input(discountInput.value, digits: digits)
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
        draft.toAmount = isCrossCurrencyTransfer ? typedReceived : nil
        draft.fee = (kind == .transfer || kind == .expense) ? fee : 0
        draft.discount = kind == .expense ? discount : 0
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
