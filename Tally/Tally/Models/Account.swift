import Foundation
import SwiftData

/// A place money lives: cash, a bank card, a credit card, savings…
///
/// The balance is never stored. It is always derived from the opening balance
/// plus every entry that touches the account (see `BalanceCalculator`).
@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = AccountKind.cash.rawValue
    var currencyCode: String = "CNY"
    var openingBalanceRaw: String = "0"
    var colorHex: String = "3D7BF7"
    var symbolName: String = "banknote"
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var includeInTotal: Bool = true
    var note: String = ""
    var isDemo: Bool = false
    var createdAt: Date = Date()

    /// Entries whose source account is this account (expense, income, transfer-out).
    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.account)
    var entries: [LedgerEntry]? = []

    /// Transfers that credit this account.
    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.toAccount)
    var incomingTransfers: [LedgerEntry]? = []

    init(
        name: String,
        kind: AccountKind,
        currencyCode: String,
        openingBalance: Decimal = 0,
        colorHex: String = "3D7BF7",
        symbolName: String? = nil,
        sortOrder: Int = 0,
        includeInTotal: Bool = true,
        isDemo: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.currencyCode = currencyCode
        self.openingBalanceRaw = DecimalCodec.encode(openingBalance)
        self.colorHex = colorHex
        self.symbolName = symbolName ?? kind.defaultSymbol
        self.sortOrder = sortOrder
        self.includeInTotal = includeInTotal
        self.isDemo = isDemo
        self.createdAt = Date()
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .cash }
        set { kindRaw = newValue.rawValue }
    }

    var openingBalance: Decimal {
        get { DecimalCodec.decode(openingBalanceRaw) }
        set { openingBalanceRaw = DecimalCodec.encode(newValue) }
    }

    var currency: CurrencyInfo { CurrencyInfo.info(for: currencyCode) }

    var entryCount: Int { (entries?.count ?? 0) + (incomingTransfers?.count ?? 0) }
}
