import Foundation
import SwiftData

/// Deleted transactions go to the trash (a separate store) and can be restored exactly as
/// they were for `retentionDays`. Restoring re-creates the entry with its original ID,
/// amounts, rate snapshot, category, splits and tags, so balances return to what they were.
@MainActor
struct TrashService {
    static let retentionDays = 30

    enum TrashError: LocalizedError, Equatable {
        case accountMissing(String)
        case destinationMissing
        case unreadable

        var errorDescription: String? {
            switch self {
            case .accountMissing(let name):
                String(localized: "The account “\(name)” no longer exists, so this transaction can't be restored.")
            case .destinationMissing:
                String(localized: "The account this transfer went to no longer exists.")
            case .unreadable:
                String(localized: "This item in the trash can't be read.")
            }
        }
    }

    let repository: LedgerRepository

    init(context: ModelContext) {
        repository = LedgerRepository(context: context)
    }

    init(repository: LedgerRepository) {
        self.repository = repository
    }

    private var context: ModelContext { repository.context }

    // MARK: Trash

    /// Moves entries out of the ledger into the trash, in one atomic save.
    func trash(_ entries: [LedgerEntry]) throws {
        let encoder = BackupService.encoder()
        for e in entries {
            let item = TrashedEntry(id: e.id, payload: try encoder.encode(BackupService.entryDTO(e)))
            item.kindRaw = e.kindRaw
            item.paidAmountRaw = DecimalCodec.encode(e.paidAmount)
            item.currencyCode = e.currencyCode
            item.date = e.date
            item.title = e.displayTitle
            item.accountName = e.account?.name ?? ""
            item.symbolName = e.displaySymbol
            item.colorHex = e.displayColorHex
            item.isDemo = e.isDemo
            context.insert(item)
            repository.audit(AuditRecord.Action.delete, "entry", id: e.id,
                             "\(e.kindRaw) \(DecimalCodec.encode(e.amount)) \(e.currencyCode) · \(e.displayTitle) → trash")
            context.delete(e)
        }
        try repository.commit()
    }

    // MARK: Restore

    /// Puts items back into the ledger. Everything is checked first; if any item can't be
    /// restored (e.g. its account was deleted) nothing changes.
    @discardableResult
    func restore(_ items: [TrashedEntry]) throws -> Int {
        let decoder = BackupService.decoder()
        let accounts = Dictionary(repository.all(Account.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let categories = Dictionary(repository.all(LedgerCategory.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let tags = Dictionary(repository.all(Tag.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let live = Set(repository.all(LedgerEntry.self).map(\.id))

        var ready: [(TrashedEntry, BackupService.EntryDTO)] = []
        for item in items {
            guard let dto = try? decoder.decode(BackupService.EntryDTO.self, from: item.payload) else {
                throw TrashError.unreadable
            }
            guard let accountID = dto.accountID, accounts[accountID] != nil else {
                throw TrashError.accountMissing(item.accountName)
            }
            if dto.kind == TransactionKind.transfer.rawValue {
                guard let to = dto.toAccountID, accounts[to] != nil else { throw TrashError.destinationMissing }
            }
            ready.append((item, dto))
        }
        var restored = 0
        for (item, dto) in ready {
            if !live.contains(dto.id) {
                BackupService.makeEntry(from: dto, in: context, accounts: accounts, categories: categories, tags: tags)
                repository.audit(AuditRecord.Action.restore, "entry", id: dto.id,
                                 "\(dto.kind) \(dto.amount) \(dto.currency) · \(item.title) ← trash")
                restored += 1
            }
            context.delete(item)
        }
        try repository.commit()
        return restored
    }

    func restore(ids: [UUID]) throws {
        let wanted = Set(ids)
        try restore(repository.all(TrashedEntry.self).filter { wanted.contains($0.id) })
    }

    // MARK: Permanent deletion

    func purge(_ items: [TrashedEntry]) throws {
        for item in items { context.delete(item) }
        try repository.commit()
    }

    /// Permanently removes items older than the retention period. Returns how many.
    @discardableResult
    func purgeExpired(now: Date = .now) -> Int {
        guard let cutoff = Calendar.ledger.date(byAdding: .day, value: -Self.retentionDays, to: now) else { return 0 }
        let expired = repository.all(TrashedEntry.self).filter { $0.deletedAt < cutoff }
        guard !expired.isEmpty else { return 0 }
        try? purge(expired)
        return expired.count
    }

    /// Days left before an item is removed for good (at least 0).
    static func daysLeft(_ item: TrashedEntry, now: Date = .now) -> Int {
        let expiry = Calendar.ledger.date(byAdding: .day, value: retentionDays, to: item.deletedAt) ?? item.deletedAt
        return max(0, Calendar.ledger.dateComponents([.day], from: now, to: expiry).day ?? 0)
    }
}
