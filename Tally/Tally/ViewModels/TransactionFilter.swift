import Foundation

/// Filter + sort state for the transaction list.
struct TransactionFilter: Equatable {
    enum DateRange: Hashable, CaseIterable, Identifiable {
        case all, thisMonth, lastMonth, last3Months, thisYear

        var id: Self { self }

        var title: String {
            switch self {
            case .all: String(localized: "All Time")
            case .thisMonth: String(localized: "This Month")
            case .lastMonth: String(localized: "Last Month")
            case .last3Months: String(localized: "Last 3 Months")
            case .thisYear: String(localized: "This Year")
            }
        }

        func interval(now: Date = .now) -> DateInterval? {
            let cal = Calendar.current
            switch self {
            case .all:
                return nil
            case .thisMonth:
                let p = Period.month(now)
                return DateInterval(start: p.start, end: p.end)
            case .lastMonth:
                let p = Period.month(now).previous
                return DateInterval(start: p.start, end: p.end)
            case .last3Months:
                let p = Period.month(now)
                let start = cal.date(byAdding: .month, value: -2, to: p.start) ?? p.start
                return DateInterval(start: start, end: p.end)
            case .thisYear:
                let p = Period.year(now)
                return DateInterval(start: p.start, end: p.end)
            }
        }
    }

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
    var range: DateRange = .all
    var minAmount: Decimal?
    var maxAmount: Decimal?
    var sort: Sort = .newest

    /// Number of active criteria (for the filter badge).
    var activeCount: Int {
        var n = 0
        if !kinds.isEmpty { n += 1 }
        if !accountIDs.isEmpty { n += 1 }
        if !categoryIDs.isEmpty { n += 1 }
        if !tagIDs.isEmpty { n += 1 }
        if range != .all { n += 1 }
        if minAmount != nil || maxAmount != nil { n += 1 }
        return n
    }

    var isActive: Bool { activeCount > 0 }

    mutating func reset() {
        let sort = self.sort
        self = TransactionFilter()
        self.sort = sort
    }

    func matches(_ e: LedgerEntry, value: Decimal) -> Bool {
        if !kinds.isEmpty && !kinds.contains(e.kind) { return false }
        if !accountIDs.isEmpty {
            let ids = [e.account?.id, e.toAccount?.id].compactMap { $0 }
            if !ids.contains(where: accountIDs.contains) { return false }
        }
        if !categoryIDs.isEmpty {
            guard let id = e.category?.id, categoryIDs.contains(id) else { return false }
        }
        if !tagIDs.isEmpty {
            let ids = Set((e.tags ?? []).map(\.id))
            if ids.isDisjoint(with: tagIDs) { return false }
        }
        if let interval = range.interval(), !(e.date >= interval.start && e.date < interval.end) { return false }
        if let minAmount, value < minAmount { return false }
        if let maxAmount, value > maxAmount { return false }
        return true
    }

    static func matchesSearch(_ e: LedgerEntry, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        var haystack: [String] = [e.note, e.currencyCode, e.kind.title]
        haystack.append(e.category?.name ?? "")
        haystack.append(e.account?.name ?? "")
        haystack.append(e.toAccount?.name ?? "")
        haystack.append(DecimalCodec.encode(e.amount))
        haystack.append(MoneyFormat.plain(e.amount))
        for tag in e.tags ?? [] { haystack.append("#" + tag.name) }
        return haystack.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    func apply(to entries: [LedgerEntry], search: String, math: LedgerMath) -> [LedgerEntry] {
        var values: [UUID: Decimal] = [:]
        let filtered = entries.filter { e in
            let v = math.value(e)
            values[e.id] = v
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
    let income: Decimal
    let expense: Decimal
}

extension TransactionFilter {
    static func groupByDay(_ entries: [LedgerEntry], math: LedgerMath) -> [DayGroup] {
        let cal = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [LedgerEntry]] = [:]
        for e in entries {
            let day = cal.startOfDay(for: e.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(e)
        }
        return order.map { day in
            let list = buckets[day] ?? []
            let s = math.summary(list)
            return DayGroup(day: day, entries: list, income: s.income, expense: s.expense)
        }
    }
}
