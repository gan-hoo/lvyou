import SwiftUI
import Observation

enum AppTab: Hashable {
    case home, transactions, statistics, budget, settings
}

/// Describes what the quick-entry sheet should open with.
struct EntryRequest: Identifiable {
    let id = UUID()
    var editing: LedgerEntry?
    var kind: TransactionKind = .expense
    var account: Account?
    var category: LedgerCategory?
    var date: Date?

    static func new(_ kind: TransactionKind = .expense, account: Account? = nil, category: LedgerCategory? = nil) -> EntryRequest {
        EntryRequest(editing: nil, kind: kind, account: account, category: category)
    }

    static func edit(_ entry: LedgerEntry) -> EntryRequest {
        EntryRequest(editing: entry, kind: entry.kind)
    }
}

/// App-wide navigation state shared through the environment.
@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .home
    var entryRequest: EntryRequest?

    func addEntry(_ kind: TransactionKind = .expense, account: Account? = nil, category: LedgerCategory? = nil) {
        entryRequest = .new(kind, account: account, category: category)
    }

    func edit(_ entry: LedgerEntry) {
        entryRequest = .edit(entry)
    }

    func show(_ tab: AppTab) {
        selectedTab = tab
    }
}
