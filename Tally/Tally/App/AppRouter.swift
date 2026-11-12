import SwiftUI
import Observation

enum AppTab: Hashable {
    case assets, transactions, analytics, budgets, settings
}

/// Describes what the quick-entry sheet should open with.
struct EntryRequest: Identifiable {
    let id = UUID()
    var editing: LedgerEntry?
    var kind: TransactionKind = .expense
    var account: Account?
    var toAccount: Account?
    var category: LedgerCategory?
    var date: Date?
    /// Pre-filled original transaction for a refund.
    var refundOf: LedgerEntry?

    static func new(_ kind: TransactionKind = .expense, account: Account? = nil, toAccount: Account? = nil, category: LedgerCategory? = nil) -> EntryRequest {
        EntryRequest(editing: nil, kind: kind, account: account, toAccount: toAccount, category: category)
    }

    static func edit(_ entry: LedgerEntry) -> EntryRequest {
        EntryRequest(editing: entry, kind: entry.kind)
    }

    static func refund(of entry: LedgerEntry) -> EntryRequest {
        EntryRequest(editing: nil, kind: .refund, account: entry.account, category: entry.category, refundOf: entry)
    }
}

/// A filtered view of the transaction list requested by another page
/// (e.g. tapping a category in Analytics or a budget).
struct TransactionQuery: Equatable {
    var period: Period?
    var categoryID: UUID?
    var accountID: UUID?
    var kinds: Set<TransactionKind> = []
}

/// App-wide navigation state shared through the environment.
@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .assets
    var entryRequest: EntryRequest?
    /// Consumed by the Transactions tab.
    var pendingQuery: TransactionQuery?

    func addEntry(_ kind: TransactionKind = .expense, account: Account? = nil, toAccount: Account? = nil, category: LedgerCategory? = nil) {
        entryRequest = .new(kind, account: account, toAccount: toAccount, category: category)
    }

    func edit(_ entry: LedgerEntry) {
        entryRequest = .edit(entry)
    }

    func refund(_ entry: LedgerEntry) {
        entryRequest = .refund(of: entry)
    }

    func show(_ tab: AppTab) {
        selectedTab = tab
    }

    func showTransactions(_ query: TransactionQuery) {
        pendingQuery = query
        selectedTab = .transactions
    }
}
