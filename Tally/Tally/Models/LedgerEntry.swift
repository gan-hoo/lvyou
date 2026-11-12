import Foundation
import SwiftData

/// A single ledger record: an expense, an income or a transfer between accounts.
///
/// Original-currency amounts and the base-currency conversion snapshot are stored
/// separately. Later exchange-rate edits therefore never rewrite history: the
/// snapshot records exactly which rate was used when the entry was saved.
@Model
final class LedgerEntry {
    var id: UUID = UUID()
    var kindRaw: String = TransactionKind.expense.rawValue

    /// Always positive, expressed in `currencyCode` (the source account's currency).
    var amountRaw: String = "0"
    var currencyCode: String = "CNY"

    var date: Date = Date()
    var note: String = ""

    var account: Account?
    /// Destination account for transfers.
    var toAccount: Account?
    /// Amount credited to `toAccount`, in the destination currency (transfers only).
    var toAmountRaw: String = ""

    var category: LedgerCategory?
    var tags: [Tag]? = []

    // Base-currency snapshot taken at save time.
    var baseCurrencyCode: String = "CNY"
    var rateToBaseRaw: String = "1"
    var baseAmountRaw: String = "0"

    var isDemo: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        kind: TransactionKind,
        amount: Decimal,
        currencyCode: String,
        date: Date,
        note: String = "",
        account: Account?,
        toAccount: Account? = nil,
        toAmount: Decimal? = nil,
        category: LedgerCategory? = nil,
        tags: [Tag] = [],
        isDemo: Bool = false
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.amountRaw = DecimalCodec.encode(amount.magnitudeValue)
        self.currencyCode = currencyCode
        self.date = date
        self.note = note
        self.account = account
        self.toAccount = toAccount
        self.toAmountRaw = toAmount.map { DecimalCodec.encode($0.magnitudeValue) } ?? ""
        self.category = category
        self.tags = tags
        self.isDemo = isDemo
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var amount: Decimal {
        get { DecimalCodec.decode(amountRaw) }
        set { amountRaw = DecimalCodec.encode(newValue.magnitudeValue) }
    }

    /// Credited amount for transfers. Falls back to `amount` for same-currency transfers.
    var toAmount: Decimal {
        get { toAmountRaw.isEmpty ? amount : DecimalCodec.decode(toAmountRaw) }
        set { toAmountRaw = DecimalCodec.encode(newValue.magnitudeValue) }
    }

    var rateToBase: Decimal {
        get { DecimalCodec.decode(rateToBaseRaw) }
        set { rateToBaseRaw = DecimalCodec.encode(newValue) }
    }

    var baseAmount: Decimal {
        get { DecimalCodec.decode(baseAmountRaw) }
        set { baseAmountRaw = DecimalCodec.encode(newValue) }
    }

    var currency: CurrencyInfo { CurrencyInfo.info(for: currencyCode) }

    var tagList: [Tag] { (tags ?? []).sorted { $0.name < $1.name } }

    /// Title used in lists: category name, or "From → To" for transfers.
    var displayTitle: String {
        switch kind {
        case .transfer:
            let from = account?.name ?? "—"
            let to = toAccount?.name ?? "—"
            return "\(from) → \(to)"
        case .expense, .income:
            return category?.name ?? String(localized: "Uncategorized")
        }
    }

    var displaySymbol: String {
        kind == .transfer ? "arrow.left.arrow.right" : (category?.symbolName ?? "questionmark")
    }

    var displayColorHex: String {
        kind == .transfer ? "5E8BFF" : (category?.colorHex ?? "8E8E93")
    }
}
