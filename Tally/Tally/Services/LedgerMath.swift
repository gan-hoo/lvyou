import Foundation

struct PeriodSummary: Equatable, Sendable {
    var income: Decimal = 0
    var expense: Decimal = 0
    var count: Int = 0

    var net: Decimal { income - expense }
}

struct CategorySlice: Identifiable, Equatable {
    let id: String
    let name: String
    let symbolName: String
    let colorHex: String
    let amount: Decimal
    let fraction: Double
    let count: Int
    let categoryID: UUID?
}

struct DayPoint: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let amount: Decimal
}

struct MonthPoint: Identifiable, Equatable {
    var id: Date { month }
    let month: Date
    let income: Decimal
    let expense: Decimal
    var net: Decimal { income - expense }
}

struct NetWorth: Equatable {
    var assets: Decimal = 0
    var liabilities: Decimal = 0
    var net: Decimal { assets + liabilities }
    /// Accounts whose currency had no exchange rate path to the base currency.
    var unconvertedCurrencies: Set<String> = []
}

/// Pure, synchronous ledger calculations. All results are in the base currency
/// unless stated otherwise, using each entry's historical rate snapshot.
struct LedgerMath {
    let base: String
    let converter: CurrencyConverter

    init(base: String, converter: CurrencyConverter) {
        self.base = base
        self.converter = converter
    }

    init(base: String, rates: [ExchangeRate]) {
        self.init(base: base, converter: CurrencyConverter(rates: rates))
    }

    // MARK: Entry values

    /// Base-currency value of an entry. Uses the stored snapshot when it was taken
    /// in the current base currency; otherwise converts with the historical rate
    /// in effect on the entry's date.
    func value(_ entry: LedgerEntry) -> Decimal {
        if entry.baseCurrencyCode == base, !entry.baseAmountRaw.isEmpty {
            return entry.baseAmount
        }
        return converter.convertOrSame(entry.amount, from: entry.currencyCode, to: base, on: entry.date)
    }

    func summary(_ entries: [LedgerEntry]) -> PeriodSummary {
        var s = PeriodSummary()
        for e in entries {
            switch e.kind {
            case .income: s.income += value(e); s.count += 1
            case .expense: s.expense += value(e); s.count += 1
            case .transfer: s.count += 1
            }
        }
        return s
    }

    // MARK: Breakdown

    func categoryBreakdown(_ entries: [LedgerEntry], kind: TransactionKind) -> [CategorySlice] {
        var totals: [String: (amount: Decimal, count: Int, category: LedgerCategory?)] = [:]
        for e in entries where e.kind == kind {
            let key = e.category?.id.uuidString ?? "none"
            let current = totals[key] ?? (amount: Decimal(0), count: 0, category: e.category)
            totals[key] = (current.amount + value(e), current.count + 1, e.category)
        }
        let grand = totals.values.sum { $0.amount }
        return totals.map { key, item in
            CategorySlice(
                id: key,
                name: item.category?.name ?? String(localized: "Uncategorized"),
                symbolName: item.category?.symbolName ?? "questionmark",
                colorHex: item.category?.colorHex ?? "8E8E93",
                amount: item.amount,
                fraction: grand > 0 ? (item.amount / grand).doubleValue : 0,
                count: item.count,
                categoryID: item.category?.id
            )
        }
        .sorted { $0.amount == $1.amount ? $0.name < $1.name : $0.amount > $1.amount }
    }

    /// Per-day totals for every day in the period (zero-filled).
    func dailySeries(_ entries: [LedgerEntry], period: Period, kind: TransactionKind) -> [DayPoint] {
        let cal = Calendar.current
        var byDay: [Date: Decimal] = [:]
        for e in entries where e.kind == kind && period.contains(e.date) {
            byDay[cal.startOfDay(for: e.date), default: 0] += value(e)
        }
        return period.days.map { DayPoint(date: $0, amount: byDay[$0] ?? 0) }
    }

    /// Running total per day. Stops at today for the current period.
    func cumulativeSeries(_ entries: [LedgerEntry], period: Period, kind: TransactionKind) -> [DayPoint] {
        var running: Decimal = 0
        let today = Date.now.startOfDay
        return dailySeries(entries, period: period, kind: kind).compactMap { point in
            guard point.date <= today else { return nil }
            running += point.amount
            return DayPoint(date: point.date, amount: running)
        }
    }

    func monthlySeries(_ entries: [LedgerEntry], months: [Period]) -> [MonthPoint] {
        months.map { month in
            let s = summary(entries.filter { month.contains($0.date) })
            return MonthPoint(month: month.start, income: s.income, expense: s.expense)
        }
    }

    // MARK: Balances

    /// Native-currency balance of every account, derived from opening balances and entries.
    func balances(accounts: [Account], entries: [LedgerEntry]) -> [UUID: Decimal] {
        var result: [UUID: Decimal] = [:]
        for a in accounts { result[a.id] = a.openingBalance }
        for e in entries {
            if let source = e.account?.id {
                switch e.kind {
                case .income: result[source, default: 0] += e.amount
                case .expense, .transfer: result[source, default: 0] -= e.amount
                }
            }
            if e.kind == .transfer, let dest = e.toAccount?.id {
                result[dest, default: 0] += e.toAmount
            }
        }
        return result
    }

    /// Total assets / liabilities across accounts that are included in totals, at today's rates.
    func netWorth(accounts: [Account], balances: [UUID: Decimal]) -> NetWorth {
        var worth = NetWorth()
        for a in accounts where a.includeInTotal && !a.isArchived {
            let native = balances[a.id] ?? a.openingBalance
            let converted: Decimal
            if let c = converter.convert(native, from: a.currencyCode, to: base) {
                converted = c
            } else {
                converted = native
                worth.unconvertedCurrencies.insert(a.currencyCode)
            }
            if converted < 0 { worth.liabilities += converted } else { worth.assets += converted }
        }
        return worth
    }

    func convertedBalance(_ account: Account, balances: [UUID: Decimal]) -> Decimal {
        converter.convertOrSame(balances[account.id] ?? account.openingBalance, from: account.currencyCode, to: base)
    }
}
