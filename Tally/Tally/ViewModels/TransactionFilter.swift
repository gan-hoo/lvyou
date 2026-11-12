import Foundation

/// Filter + sort state for the transaction list (the period is chosen separately).
struct TransactionFilter: Equatable {
    enum Sort: String, CaseIterable, Identifiable {
        case newest, oldest, largest, smallest

        var id: String { rawValue }

        var title: String {
            switch self {
            case .newest: String(localized: "Newest First")
            case .oldest: String(localized: "Oldest First")
            case .largest: String(localized: "Largest Amount")
            case .smallest: String(localized: "Smallest Amount")
            }
        }

        var symbol: String {
            switch self {
            case .newest: "arrow.down"
            case .oldest: "arrow.up"
            case .largest: "arrow.down.right"
            case .smallest: "arrow.up.right"
            }
        }

        var groupsByDay: Bool { self == .newest || self == .oldest }
    }

    var kinds: Set<TransactionKind> = []
    var accountIDs: Set<UUID> = []
    var categoryIDs: Set<UUID> = []
    var tagIDs: Set<UUID> = []
    var minAmount: Decimal?
    var maxAmount: Decimal?
    var sort: Sort = .newest

    var activeCount: Int {
        var n = 0
        if !kinds.isEmpty { n += 1 }
        if !accountIDs.isEmpty { n += 1 }
        if !categoryIDs.isEmpty { n += 1 }
        if !tagIDs.isEmpty { n += 1 }
        if minAmount != nil || maxAmount != nil { n += 1 }
        return n
    }

    var isActive: Bool { activeCount > 0 }

    mutating func reset() {
        let sort = self.sort
        self = TransactionFilter()
        self.sort = sort
    }

    /// `value` is the entry's base-currency value (nil when pending conversion).
    func matches(_ e: LedgerEntry, value: Decimal?) -> Bool {
        if !kinds.isEmpty && !kinds.contains(e.kind) { return false }
        if !accountIDs.isEmpty {
            let ids = [e.account?.id, e.toAccount?.id].compactMap { $0 }
            if !ids.contains(where: accountIDs.contains) { return false }
        }
        if !categoryIDs.isEmpty {
            var ids = Set(e.splitList.compactMap { $0.category?.id })
            if let id = e.category?.id { ids.insert(id) }
            if let fee = UUID(uuidString: e.feeCategoryIDRaw), e.fee > 0 { ids.insert(fee) }
            if ids.isDisjoint(with: categoryIDs) { return false }
        }
        if !tagIDs.isEmpty {
            if Set((e.tags ?? []).map(\.id)).isDisjoint(with: tagIDs) { return false }
        }
        if minAmount != nil || maxAmount != nil {
            guard let value else { return false }
            if let minAmount, value < minAmount { return false }
            if let maxAmount, value > maxAmount { return false }
        }
        return true
    }

    static func matchesSearch(_ e: LedgerEntry, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        var haystack: [String] = [e.note, e.payee, e.currencyCode, e.kind.title]
        haystack.append(e.category?.name ?? "")
        haystack.append(e.account?.name ?? "")
        haystack.append(e.toAccount?.name ?? "")
        haystack.append(DecimalCodec.encode(e.amount))
        haystack.append(MoneyFormat.plain(e.amount))
        for s in e.splitList { haystack.append(s.category?.name ?? "") }
        for tag in e.tags ?? [] { haystack.append("#" + tag.name) }
        return haystack.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    func apply(to entries: [LedgerEntry], period: Period?, search: String, engine: FinanceEngine) -> [LedgerEntry] {
        var values: [UUID: Decimal] = [:]
        let filtered = entries.filter { e in
            if let period, !period.contains(e.date) { return false }
            let v = engine.baseValue(EntryValue(e))
            if let v { values[e.id] = v }
            return matches(e, value: v) && Self.matchesSearch(e, query: search)
        }
        switch sort {
        case .newest: return filtered.sorted { $0.date > $1.date }
        case .oldest: return filtered.sorted { $0.date < $1.date }
        case .largest: return filtered.sorted { (values[$0.id] ?? 0) > (values[$1.id] ?? 0) }
        case .smallest: return filtered.sorted { (values[$0.id] ?? 0) < (values[$1.id] ?? 0) }
        }
    }
}

struct DayGroup: Identifiable {
    var id: Date { day }
    let day: Date
    let entries: [LedgerEntry]
    var income: Decimal = 0
    var expense: Decimal = 0

    /// Groups entries by calendar day, keeping their order; totals use `engine` when given.
    static func group(_ entries: [LedgerEntry], engine: FinanceEngine? = nil) -> [DayGroup] {
        let cal = Calendar.ledger
        var order: [Date] = []
        var buckets: [Date: [LedgerEntry]] = [:]
        for e in entries {
            let day = cal.startOfDay(for: e.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(e)
        }
        return order.map { day in
            let list = buckets[day] ?? []
            var g = DayGroup(day: day, entries: list)
            if let engine {
                let r = engine.report(list.map(EntryValue.init))
                g.income = r.income
                g.expense = r.expense
            }
            return g
        }
    }
}
