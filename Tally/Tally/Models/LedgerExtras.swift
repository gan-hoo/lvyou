import Foundation
import SwiftData

/// One part of a split transaction. Splits of an entry always add up to the entry amount.
@Model
final class TransactionSplit {
    var id: UUID = UUID()
    /// Positive amount in the parent entry's currency.
    var amountRaw: String = "0"
    var note: String = ""
    var sortOrder: Int = 0
    var entry: LedgerEntry?
    var category: LedgerCategory?

    init(amount: Decimal, note: String = "", sortOrder: Int = 0) {
        self.id = UUID()
        self.amountRaw = DecimalCodec.encode(amount.magnitudeValue)
        self.note = note
        self.sortOrder = sortOrder
    }

    var amount: Decimal {
        get { DecimalCodec.decode(amountRaw) }
        set { amountRaw = DecimalCodec.encode(newValue.magnitudeValue) }
    }
}

/// A recurring plan (rent, salary, subscriptions…). Plans never touch balances;
/// `RecurringService` creates real entries once each occurrence is due.
@Model
final class RecurringRule {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = TransactionKind.expense.rawValue
    var amountRaw: String = "0"
    var accountIDRaw: String = ""
    var toAccountIDRaw: String = ""
    var toAmountRaw: String = ""
    var categoryIDRaw: String = ""
    var note: String = ""
    var payee: String = ""
    var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
    /// Every `interval` units of `frequency` (e.g. 2 + weekly = fortnightly).
    var interval: Int = 1
    var startDate: Date = Date()
    var endDate: Date?
    /// The next scheduled occurrence that has not been booked yet.
    var nextDate: Date = Date()
    /// Occurrences already booked; occurrence n is start + n × interval.
    var generatedCount: Int = 0
    var isActive: Bool = true
    var isDemo: Bool = false
    var createdAt: Date = Date()

    init(name: String, kind: TransactionKind, amount: Decimal, frequency: RecurrenceFrequency, interval: Int = 1, startDate: Date) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.amountRaw = DecimalCodec.encode(amount.magnitudeValue)
        self.frequencyRaw = frequency.rawValue
        self.interval = max(1, interval)
        self.startDate = startDate
        self.nextDate = startDate
        self.createdAt = Date()
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var amount: Decimal {
        get { DecimalCodec.decode(amountRaw) }
        set { amountRaw = DecimalCodec.encode(newValue.magnitudeValue) }
    }

    var accountID: UUID? {
        get { UUID(uuidString: accountIDRaw) }
        set { accountIDRaw = newValue?.uuidString ?? "" }
    }

    var toAccountID: UUID? {
        get { UUID(uuidString: toAccountIDRaw) }
        set { toAccountIDRaw = newValue?.uuidString ?? "" }
    }

    var categoryID: UUID? {
        get { UUID(uuidString: categoryIDRaw) }
        set { categoryIDRaw = newValue?.uuidString ?? "" }
    }
}

/// Append-only log of changes that matter for auditing (edits, deletions,
/// balance adjustments, restores, imports).
@Model
final class AuditRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var action: String = ""
    var entityKind: String = ""
    var entityIDRaw: String = ""
    var summary: String = ""

    init(action: String, entityKind: String, entityID: UUID?, summary: String) {
        self.id = UUID()
        self.date = Date()
        self.action = action
        self.entityKind = entityKind
        self.entityIDRaw = entityID?.uuidString ?? ""
        self.summary = summary
    }

    enum Action {
        static let create = "create"
        static let update = "update"
        static let delete = "delete"
        static let adjust = "adjust"
        static let restore = "restore"
        static let importCSV = "import"
    }
}

/// A deleted transaction, kept for `TrashService.retentionDays` so it can be restored.
/// It lives apart from the ledger: balances, reports, budgets and exports only ever read
/// `LedgerEntry`, so nothing in the trash can be counted by mistake.
@Model
final class TrashedEntry {
    /// The original entry's ID (restored under the same ID).
    var id: UUID = UUID()
    var deletedAt: Date = Date()
    /// JSON of `BackupService.EntryDTO`: everything needed to rebuild the entry.
    var payload: Data = Data()
    // Display copies, so the trash can be listed without decoding.
    var kindRaw: String = TransactionKind.expense.rawValue
    var paidAmountRaw: String = "0"
    var currencyCode: String = "CNY"
    var date: Date = Date()
    var title: String = ""
    var accountName: String = ""
    var symbolName: String = "questionmark"
    var colorHex: String = "8E8E93"
    var isDemo: Bool = false

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
        self.deletedAt = Date()
    }

    var kind: TransactionKind { TransactionKind(rawValue: kindRaw) ?? .expense }
    var paidAmount: Decimal { DecimalCodec.decode(paidAmountRaw) }
}
