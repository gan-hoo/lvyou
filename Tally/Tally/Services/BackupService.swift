import Foundation
import SwiftData
import CryptoKit

/// Versioned, checksummed JSON backups of the whole ledger.
@MainActor
struct BackupService {
    static let format = "tally-backup"
    static let schemaVersion = 3

    struct File: Codable {
        var format: String
        var schemaVersion: Int
        var appVersion: String
        var createdAt: Date
        var checksum: String
        var payload: Payload
    }

    struct Payload: Codable, Equatable {
        var accounts: [AccountDTO] = []
        var categories: [CategoryDTO] = []
        var tags: [TagDTO] = []
        var entries: [EntryDTO] = []
        var budgets: [BudgetDTO] = []
        var rules: [RuleDTO] = []
        var rates: [RateDTO] = []
    }

    struct AccountDTO: Codable, Equatable {
        var id: UUID; var name: String; var kind: String; var currency: String
        var openingBalance: String; var openingDate: Date; var color: String; var symbol: String
        var sortOrder: Int; var archived: Bool; var includeInTotal: Bool; var note: String
        var group: String; var reconciledBalance: String; var reconciledAt: Date?
    }

    struct CategoryDTO: Codable, Equatable {
        var id: UUID; var name: String; var kind: String; var symbol: String; var color: String
        var sortOrder: Int; var archived: Bool
    }

    struct TagDTO: Codable, Equatable {
        var id: UUID; var name: String; var color: String
    }

    struct SplitDTO: Codable, Equatable {
        var amount: String; var categoryID: UUID?; var note: String
    }

    struct EntryDTO: Codable, Equatable {
        var id: UUID; var kind: String; var amount: String; var currency: String; var date: Date
        var note: String; var payee: String; var accountID: UUID?; var toAccountID: UUID?
        var toAmount: String; var fee: String; var feeCategoryID: String; var categoryID: UUID?
        var tagIDs: [UUID]; var splits: [SplitDTO]
        var baseCurrency: String; var rateToBase: String; var baseAmount: String
        var refundOf: String; var adjustmentDelta: String; var adjustmentPrevious: String
        var recurringRuleID: String; var occurrenceDate: Date?
        var createdAt: Date; var updatedAt: Date
    }

    struct BudgetDTO: Codable, Equatable {
        var id: UUID; var amount: String; var currency: String; var categoryID: UUID?
        var threshold: Double; var period: String; var customLengthDays: Int; var anchorDate: Date
        var rollover: Bool; var excluded: String; var createdAt: Date
    }

    struct RuleDTO: Codable, Equatable {
        var id: UUID; var name: String; var kind: String; var amount: String
        var accountID: String; var toAccountID: String; var toAmount: String; var categoryID: String
        var note: String; var payee: String; var frequency: String; var interval: Int
        var startDate: Date; var endDate: Date?; var generatedCount: Int; var active: Bool
    }

    struct RateDTO: Codable, Equatable {
        var id: UUID; var base: String; var quote: String; var rate: String; var date: Date; var source: String
    }

    enum BackupError: LocalizedError {
        case notABackup
        case newerVersion(Int)
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .notABackup: String(localized: "This file is not a Tally backup.")
            case .newerVersion: String(localized: "This backup was made by a newer version of Tally.")
            case .checksumMismatch: String(localized: "The backup is damaged (checksum mismatch).")
            }
        }
    }

    enum RestoreMode {
        /// Adds records whose IDs are not in the ledger yet.
        case merge
        /// Erases the ledger first.
        case replace
    }

    struct RestoreSummary: Equatable {
        var added = 0
        var skipped = 0
    }

    let repository: LedgerRepository

    init(context: ModelContext) {
        repository = LedgerRepository(context: context)
    }

    // MARK: Encoding

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        // Exact round trip (reference-date seconds), so checksums are reproducible.
        e.dateEncodingStrategy = .deferredToDate
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        return d
    }

    static func checksum(_ payload: Payload) throws -> String {
        let data = try encoder().encode(payload)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Export

    func makePayload() -> Payload {
        var p = Payload()
        p.accounts = repository.all(Account.self).map {
            AccountDTO(id: $0.id, name: $0.name, kind: $0.kindRaw, currency: $0.currencyCode,
                       openingBalance: $0.openingBalanceRaw, openingDate: $0.openingDate, color: $0.colorHex,
                       symbol: $0.symbolName, sortOrder: $0.sortOrder, archived: $0.isArchived,
                       includeInTotal: $0.includeInTotal, note: $0.note, group: $0.groupName,
                       reconciledBalance: $0.reconciledBalanceRaw, reconciledAt: $0.reconciledAt)
        }
        p.categories = repository.all(LedgerCategory.self).map {
            CategoryDTO(id: $0.id, name: $0.name, kind: $0.kindRaw, symbol: $0.symbolName, color: $0.colorHex,
                        sortOrder: $0.sortOrder, archived: $0.isArchived)
        }
        p.tags = repository.all(Tag.self).map { TagDTO(id: $0.id, name: $0.name, color: $0.colorHex) }
        p.entries = repository.all(LedgerEntry.self).sorted { $0.date < $1.date }.map { e in
            EntryDTO(id: e.id, kind: e.kindRaw, amount: e.amountRaw, currency: e.currencyCode, date: e.date,
                     note: e.note, payee: e.payee, accountID: e.account?.id, toAccountID: e.toAccount?.id,
                     toAmount: e.toAmountRaw, fee: e.feeRaw, feeCategoryID: e.feeCategoryIDRaw, categoryID: e.category?.id,
                     tagIDs: (e.tags ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString },
                     splits: e.splitList.map { SplitDTO(amount: $0.amountRaw, categoryID: $0.category?.id, note: $0.note) },
                     baseCurrency: e.baseCurrencyCode, rateToBase: e.rateToBaseRaw, baseAmount: e.baseAmountRaw,
                     refundOf: e.refundOfIDRaw, adjustmentDelta: e.adjustmentDeltaRaw,
                     adjustmentPrevious: e.adjustmentPreviousBalanceRaw, recurringRuleID: e.recurringRuleIDRaw,
                     occurrenceDate: e.occurrenceDate, createdAt: e.createdAt, updatedAt: e.updatedAt)
        }
        p.budgets = repository.all(Budget.self).map {
            BudgetDTO(id: $0.id, amount: $0.amountRaw, currency: $0.currencyCode, categoryID: $0.category?.id,
                      threshold: $0.alertThreshold, period: $0.periodRaw, customLengthDays: $0.customLengthDays,
                      anchorDate: $0.anchorDate, rollover: $0.rollover, excluded: $0.excludedCategoryIDsRaw,
                      createdAt: $0.createdAt)
        }
        p.rules = repository.all(RecurringRule.self).map {
            RuleDTO(id: $0.id, name: $0.name, kind: $0.kindRaw, amount: $0.amountRaw, accountID: $0.accountIDRaw,
                    toAccountID: $0.toAccountIDRaw, toAmount: $0.toAmountRaw, categoryID: $0.categoryIDRaw,
                    note: $0.note, payee: $0.payee, frequency: $0.frequencyRaw, interval: $0.interval,
                    startDate: $0.startDate, endDate: $0.endDate, generatedCount: $0.generatedCount, active: $0.isActive)
        }
        p.rates = repository.all(ExchangeRate.self).filter { !$0.isDemo }.map {
            RateDTO(id: $0.id, base: $0.baseCode, quote: $0.quoteCode, rate: $0.rateRaw, date: $0.effectiveDate, source: $0.source)
        }
        return p
    }

    func exportData(now: Date = .now) throws -> Data {
        let payload = makePayload()
        let file = File(
            format: Self.format,
            schemaVersion: Self.schemaVersion,
            appVersion: Bundle.main.versionString,
            createdAt: now,
            checksum: try Self.checksum(payload),
            payload: payload
        )
        return try Self.encoder().encode(file)
    }

    func writeBackupFile(now: Date = .now) throws -> URL {
        let stamp = now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tally-Backup-\(stamp).json")
        try exportData(now: now).write(to: url, options: .atomic)
        return url
    }

    // MARK: Import

    /// Decodes and verifies a backup (format, version, checksum) without changing anything.
    static func read(_ data: Data) throws -> File {
        guard let file = try? decoder().decode(File.self, from: data), file.format == format else {
            throw BackupError.notABackup
        }
        guard file.schemaVersion <= schemaVersion else { throw BackupError.newerVersion(file.schemaVersion) }
        guard try checksum(file.payload) == file.checksum else { throw BackupError.checksumMismatch }
        return file
    }

    @discardableResult
    func restore(_ file: File, mode: RestoreMode) throws -> RestoreSummary {
        if mode == .replace { try repository.eraseAllData(reseed: false) }
        let context = repository.context
        var summary = RestoreSummary()
        let p = file.payload

        var accounts = Dictionary(repository.all(Account.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var categories = Dictionary(repository.all(LedgerCategory.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var tags = Dictionary(repository.all(Tag.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let entryIDs = Set(repository.all(LedgerEntry.self).map(\.id))
        let budgetIDs = Set(repository.all(Budget.self).map(\.id))
        let ruleIDs = Set(repository.all(RecurringRule.self).map(\.id))
        let rateIDs = Set(repository.all(ExchangeRate.self).map(\.id))

        for d in p.accounts {
            guard accounts[d.id] == nil else { summary.skipped += 1; continue }
            let a = Account(name: d.name, kind: AccountKind(rawValue: d.kind) ?? .cash, currencyCode: d.currency,
                            colorHex: d.color, symbolName: d.symbol, sortOrder: d.sortOrder,
                            includeInTotal: d.includeInTotal, openingDate: d.openingDate)
            a.id = d.id
            a.openingBalanceRaw = d.openingBalance
            a.isArchived = d.archived
            a.note = d.note
            a.groupName = d.group
            a.reconciledBalanceRaw = d.reconciledBalance
            a.reconciledAt = d.reconciledAt
            context.insert(a)
            accounts[d.id] = a
            summary.added += 1
        }
        var byName = Dictionary(categories.values.map { ($0.kindRaw + "|" + $0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for d in p.categories {
            if categories[d.id] != nil { summary.skipped += 1; continue }
            // Same-named category of the same kind already exists: reuse it.
            if let existing = byName[d.kind + "|" + d.name] {
                categories[d.id] = existing
                summary.skipped += 1
                continue
            }
            let c = LedgerCategory(name: d.name, kind: CategoryKind(rawValue: d.kind) ?? .expense,
                                   symbolName: d.symbol, colorHex: d.color, sortOrder: d.sortOrder)
            c.id = d.id
            c.isArchived = d.archived
            context.insert(c)
            categories[d.id] = c
            byName[d.kind + "|" + d.name] = c
            summary.added += 1
        }
        for d in p.tags {
            guard tags[d.id] == nil else { summary.skipped += 1; continue }
            let t = Tag(name: d.name, colorHex: d.color)
            t.id = d.id
            context.insert(t)
            tags[d.id] = t
            summary.added += 1
        }
        for d in p.entries {
            guard !entryIDs.contains(d.id) else { summary.skipped += 1; continue }
            let e = LedgerEntry(kind: TransactionKind(rawValue: d.kind) ?? .expense, amount: DecimalCodec.decode(d.amount),
                                currencyCode: d.currency, date: d.date, note: d.note)
            e.id = d.id
            context.insert(e)
            e.payee = d.payee
            e.account = d.accountID.flatMap { accounts[$0] }
            e.toAccount = d.toAccountID.flatMap { accounts[$0] }
            e.toAmountRaw = d.toAmount
            e.feeRaw = d.fee
            e.feeCategoryIDRaw = d.feeCategoryID
            e.category = d.categoryID.flatMap { categories[$0] }
            e.tags = d.tagIDs.compactMap { tags[$0] }
            e.baseCurrencyCode = d.baseCurrency
            e.rateToBaseRaw = d.rateToBase
            e.baseAmountRaw = d.baseAmount
            e.refundOfIDRaw = d.refundOf
            e.adjustmentDeltaRaw = d.adjustmentDelta
            e.adjustmentPreviousBalanceRaw = d.adjustmentPrevious
            e.recurringRuleIDRaw = d.recurringRuleID
            e.occurrenceDate = d.occurrenceDate
            e.createdAt = d.createdAt
            e.updatedAt = d.updatedAt
            for (i, s) in d.splits.enumerated() {
                let split = TransactionSplit(amount: DecimalCodec.decode(s.amount), note: s.note, sortOrder: i)
                context.insert(split)
                split.category = s.categoryID.flatMap { categories[$0] }
                split.entry = e
            }
            summary.added += 1
        }
        for d in p.budgets {
            guard !budgetIDs.contains(d.id) else { summary.skipped += 1; continue }
            let b = Budget(amount: DecimalCodec.decode(d.amount), currencyCode: d.currency, alertThreshold: d.threshold)
            b.id = d.id
            context.insert(b)
            b.category = d.categoryID.flatMap { categories[$0] }
            b.periodRaw = d.period
            b.customLengthDays = d.customLengthDays
            b.anchorDate = d.anchorDate
            b.rollover = d.rollover
            b.excludedCategoryIDsRaw = d.excluded
            b.createdAt = d.createdAt
            summary.added += 1
        }
        for d in p.rules {
            guard !ruleIDs.contains(d.id) else { summary.skipped += 1; continue }
            let r = RecurringRule(name: d.name, kind: TransactionKind(rawValue: d.kind) ?? .expense,
                                  amount: DecimalCodec.decode(d.amount),
                                  frequency: RecurrenceFrequency(rawValue: d.frequency) ?? .monthly,
                                  interval: d.interval, startDate: d.startDate)
            r.id = d.id
            r.accountIDRaw = d.accountID
            r.toAccountIDRaw = d.toAccountID
            r.toAmountRaw = d.toAmount
            r.categoryIDRaw = d.categoryID
            r.note = d.note
            r.payee = d.payee
            r.endDate = d.endDate
            r.generatedCount = d.generatedCount
            r.nextDate = Recurrence.occurrence(d.generatedCount, start: d.startDate, frequency: r.frequency, interval: d.interval)
            r.isActive = d.active
            context.insert(r)
            summary.added += 1
        }
        for d in p.rates {
            guard !rateIDs.contains(d.id) else { summary.skipped += 1; continue }
            let rate = ExchangeRate(baseCode: d.base, quoteCode: d.quote, rate: DecimalCodec.decode(d.rate),
                                    effectiveDate: d.date, source: d.source)
            rate.id = d.id
            context.insert(rate)
            summary.added += 1
        }
        repository.audit(AuditRecord.Action.restore, "backup", id: nil,
                         "\(mode == .replace ? "replace" : "merge") +\(summary.added) =\(summary.skipped)")
        try repository.commit()
        return summary
    }
}
