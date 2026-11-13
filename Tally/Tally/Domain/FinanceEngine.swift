import Foundation

/// Base-currency money that may be partially unavailable (missing exchange rates).
struct ConvertedTotal: Equatable, Sendable {
    var amount: Decimal = 0
    /// Number of items left out because no exchange rate was available.
    var pendingCount: Int = 0
}

struct PeriodReport: Equatable, Sendable {
    var income: Decimal = 0
    /// Spending net of refunds, including transfer fees.
    var expense: Decimal = 0
    var refunds: Decimal = 0
    var fees: Decimal = 0
    /// Expense discounts (already netted out of `expense`).
    var discounts: Decimal = 0
    /// Entries in the period, transfers and adjustments included.
    var count: Int = 0
    var pendingCount: Int = 0

    var net: Decimal { income - expense }
}

struct CategoryShare: Identifiable, Equatable, Sendable {
    var id: String { categoryID?.uuidString ?? "none" }
    let categoryID: UUID?
    let amount: Decimal
    let fraction: Double
    let count: Int
}

struct DayPoint: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let amount: Decimal
}

struct MonthPoint: Identifiable, Equatable, Sendable {
    var id: Date { month }
    let month: Date
    let income: Decimal
    let expense: Decimal
    var net: Decimal { income - expense }
}

struct NetWorth: Equatable, Sendable {
    var assets: Decimal = 0
    /// Positive amount owed.
    var liabilities: Decimal = 0
    var net: Decimal { assets - liabilities }
    /// Accounts left out of the totals because their currency has no rate to the base currency.
    var pendingAccountIDs: Set<UUID> = []
}

/// Pure finance calculations over a `LedgerSnapshot`. Implements docs/FINANCE_RULES.md.
struct FinanceEngine: Sendable {
    let base: String
    let converter: CurrencyConverter

    init(base: String, converter: CurrencyConverter) {
        self.base = base
        self.converter = converter
    }

    init(base: String, rates: [RatePoint]) {
        self.init(base: base, converter: CurrencyConverter(points: rates))
    }

    private var baseDigits: Int { CurrencyInfo.info(for: base).fractionDigits }

    // MARK: - Conversion

    /// Rate used to express an entry in the base currency: the saved snapshot when it
    /// was taken in the current base currency, else the historical rate on the entry's date.
    func rateToBase(_ e: EntryValue) -> Decimal? {
        if let s = e.snapshot, s.base == base { return s.rate }
        return converter.rate(from: e.currency, to: base, on: e.date)
    }

    /// Base-currency value of the whole entry amount (nil = pending conversion).
    func baseValue(_ e: EntryValue) -> Decimal? {
        if let s = e.snapshot, s.base == base { return s.baseAmount }
        guard let r = converter.rate(from: e.currency, to: base, on: e.date) else { return nil }
        return (e.amount * r).rounded(scale: baseDigits)
    }

    /// Base value of part of an entry (fees, splits) at the entry's rate.
    func baseValue(_ amount: Decimal, of e: EntryValue) -> Decimal? {
        guard let r = rateToBase(e) else { return nil }
        return (amount * r).rounded(scale: baseDigits)
    }

    /// Splits an already-rounded total across parts in proportion, giving any
    /// rounding remainder to the last part so the parts add up exactly.
    static func allocate(_ total: Decimal, across parts: [Decimal], scale: Int) -> [Decimal] {
        let sum = parts.sum { $0 }
        guard sum != 0, !parts.isEmpty else { return parts.map { _ in 0 } }
        var result: [Decimal] = []
        var allocated: Decimal = 0
        for (i, p) in parts.enumerated() {
            if i == parts.count - 1 {
                result.append(total - allocated)
            } else {
                let share = (total * p / sum).rounded(scale: scale)
                result.append(share)
                allocated += share
            }
        }
        return result
    }

    // MARK: - Balances

    /// Native-currency balance of each account.
    func balances(accounts: [AccountValue], entries: [EntryValue]) -> [UUID: Decimal] {
        var result: [UUID: Decimal] = [:]
        var openings: [UUID: Date] = [:]
        for a in accounts {
            result[a.id] = a.openingBalance
            openings[a.id] = a.openingDate
        }
        for e in entries {
            if let source = e.accountID, let opening = openings[source], e.date >= opening {
                switch e.kind {
                case .expense: result[source, default: 0] -= (e.amount - e.discount + e.fee)
                case .income, .refund: result[source, default: 0] += e.amount
                case .transfer: result[source, default: 0] -= (e.amount + e.fee)
                case .adjustment: result[source, default: 0] += e.adjustmentDelta
                }
            }
            if e.kind == .transfer, let dest = e.toAccountID, let opening = openings[dest], e.date >= opening {
                result[dest, default: 0] += e.toAmount
            }
        }
        return result
    }

    /// Assets / liabilities / net worth at current rates. Accounts without a rate are
    /// reported as pending and excluded — never converted at 1:1.
    func netWorth(accounts: [AccountValue], balances: [UUID: Decimal], on date: Date = .now) -> NetWorth {
        var worth = NetWorth()
        for a in accounts where a.includeInNetWorth && !a.isArchived {
            let native = balances[a.id] ?? a.openingBalance
            guard native != 0 else { continue }
            guard let converted = converter.convert(native, from: a.currency, to: base, on: date) else {
                worth.pendingAccountIDs.insert(a.id)
                continue
            }
            if converted >= 0 {
                worth.assets += converted
            } else {
                worth.liabilities += -converted
            }
        }
        worth.assets = worth.assets.canonical
        worth.liabilities = worth.liabilities.canonical
        return worth
    }

    // MARK: - Contributions

    /// Signed base-currency spending contributions of one entry, per category.
    /// Expenses (or their splits) and transfer fees add; refunds subtract.
    /// Returns nil when the entry needs a conversion that is not available.
    func expenseContributions(_ e: EntryValue) -> [(categoryID: UUID?, amount: Decimal)]? {
        switch e.kind {
        case .expense:
            guard var goods = baseValue(e) else { return nil }
            if e.discount > 0 {
                guard let discount = baseValue(e.discount, of: e) else { return nil }
                goods -= discount
            }
            var parts: [(categoryID: UUID?, amount: Decimal)]
            if e.splits.isEmpty {
                parts = [(e.categoryID, goods)]
            } else {
                // The discount is shared across the parts in proportion to their amounts.
                let shares = Self.allocate(goods, across: e.splits.map(\.amount), scale: baseDigits)
                parts = zip(e.splits, shares).map { ($0.categoryID, $1) }
            }
            if e.fee > 0 {
                guard let fee = baseValue(e.fee, of: e) else { return nil }
                parts.append((e.feeCategoryID, fee))
            }
            return parts
        case .refund:
            guard let total = baseValue(e) else { return nil }
            return [(e.categoryID, -total)]
        case .transfer:
            guard e.fee > 0 else { return [] }
            guard let fee = baseValue(e.fee, of: e) else { return nil }
            return [(e.feeCategoryID, fee)]
        case .income, .adjustment:
            return []
        }
    }

    // MARK: - Reports

    func report(_ entries: [EntryValue], in period: Period? = nil, endingBefore cutoff: Date? = nil) -> PeriodReport {
        var r = PeriodReport()
        for e in entries {
            if let period, !period.contains(e.date) { continue }
            if let cutoff, e.date >= cutoff { continue }
            r.count += 1
            switch e.kind {
            case .income:
                guard let v = baseValue(e) else { r.pendingCount += 1; continue }
                r.income += v
            case .expense, .refund, .transfer:
                guard let parts = expenseContributions(e) else { r.pendingCount += 1; continue }
                let total = parts.sum { $0.amount }
                r.expense += total
                if e.kind == .refund { r.refunds += -total }
                if e.fee > 0, let fee = baseValue(e.fee, of: e) { r.fees += fee }
                if e.kind == .expense, e.discount > 0, let discount = baseValue(e.discount, of: e) { r.discounts += discount }
            case .adjustment:
                break
            }
        }
        return r
    }

    /// Net spending (or income) per category in the period, largest first.
    func categoryShares(_ entries: [EntryValue], in period: Period, kind: CategoryKind) -> [CategoryShare] {
        var totals: [UUID?: (Decimal, Int)] = [:]
        for e in entries where period.contains(e.date) {
            switch kind {
            case .expense:
                guard let parts = expenseContributions(e) else { continue }
                for p in parts {
                    let cur = totals[p.categoryID] ?? (0, 0)
                    totals[p.categoryID] = (cur.0 + p.amount, cur.1 + 1)
                }
            case .income:
                guard e.kind == .income, let v = baseValue(e) else { continue }
                let cur = totals[e.categoryID] ?? (0, 0)
                totals[e.categoryID] = (cur.0 + v, cur.1 + 1)
            }
        }
        let positive = totals.filter { $0.value.0 > 0 }
        let grand = positive.values.sum { $0.0 }
        return positive.map { id, value in
            CategoryShare(
                categoryID: id,
                amount: value.0,
                fraction: grand > 0 ? (value.0 / grand).doubleValue : 0,
                count: value.1
            )
        }
        .sorted { $0.amount.isSameAmount(as: $1.amount) ? $0.id < $1.id : $0.amount > $1.amount }
    }

    /// Net spending per day (zero-filled).
    func dailyExpense(_ entries: [EntryValue], in period: Period) -> [DayPoint] {
        let cal = Calendar.ledger
        var byDay: [Date: Decimal] = [:]
        for e in entries where period.contains(e.date) {
            guard let parts = expenseContributions(e), !parts.isEmpty else { continue }
            byDay[cal.startOfDay(for: e.date), default: 0] += parts.sum { $0.amount }
        }
        return period.days.map { DayPoint(date: $0, amount: byDay[$0] ?? 0) }
    }

    func monthly(_ entries: [EntryValue], months: [Period]) -> [MonthPoint] {
        guard let first = months.first?.start, let last = months.last?.end else { return [] }
        let relevant = entries.filter { $0.date >= first && $0.date < last }
        return months.map { m in
            let r = report(relevant, in: m)
            return MonthPoint(month: m.start, income: r.income, expense: r.expense)
        }
    }
}
