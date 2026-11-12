import Foundation

/// Value snapshot of an exchange rate, decoupled from SwiftData for fast lookups and testing.
struct RatePoint: Hashable, Sendable {
    let base: String
    let quote: String
    let rate: Decimal
    let date: Date
}

/// Converts between currencies using the *historical* rate in effect on a given day.
///
/// Lookup order for `from → to` on `date`:
/// 1. the latest direct rate effective on or before `date`
/// 2. the inverse of the latest reverse rate on or before `date`
/// 3. a cross rate through a pivot currency (USD, then CNY, then any)
/// 4. the earliest rate after `date` when nothing older exists
struct CurrencyConverter: Sendable {
    private var table: [String: [RatePoint]] = [:]

    init(points: [RatePoint]) {
        for p in points where p.rate > 0 {
            table[Self.key(p.base, p.quote), default: []].append(p)
        }
        for k in table.keys {
            table[k]?.sort { $0.date < $1.date }
        }
    }

    init(rates: [ExchangeRate]) {
        self.init(points: rates.map { RatePoint(base: $0.baseCode, quote: $0.quoteCode, rate: $0.rate, date: $0.effectiveDate) })
    }

    private static func key(_ a: String, _ b: String) -> String { a + "/" + b }

    var currencies: Set<String> {
        var set = Set<String>()
        for list in table.values { for p in list { set.insert(p.base); set.insert(p.quote) } }
        return set
    }

    /// Rate such that `1 from = rate to`, or nil when no path exists.
    func rate(from: String, to: String, on date: Date = .now) -> Decimal? {
        if from == to { return 1 }
        if let direct = directRate(from: from, to: to, on: date) { return direct }
        let pivots = ["USD", "CNY", "EUR"] + currencies.sorted()
        for pivot in pivots where pivot != from && pivot != to {
            // Express both currencies per 1 unit of the pivot and divide; this keeps
            // results exact when rates are stored as pivot quotes (e.g. USD/CNY, USD/AUD).
            if let perFrom = directRate(from: pivot, to: from, on: date),
               let perTo = directRate(from: pivot, to: to, on: date),
               perFrom != 0 {
                return (perTo / perFrom).rounded(scale: 10)
            }
        }
        return nil
    }

    func convert(_ amount: Decimal, from: String, to: String, on date: Date = .now) -> Decimal? {
        guard let r = rate(from: from, to: to, on: date) else { return nil }
        return (amount * r).rounded(scale: CurrencyInfo.info(for: to).fractionDigits)
    }

    /// Converts, falling back to the unconverted amount if no rate exists (callers flag this case).
    func convertOrSame(_ amount: Decimal, from: String, to: String, on date: Date = .now) -> Decimal {
        convert(amount, from: from, to: to, on: date) ?? amount
    }

    private func directRate(from: String, to: String, on date: Date) -> Decimal? {
        let forward = latest(in: table[Self.key(from, to)], onOrBefore: date)
        let backward = latest(in: table[Self.key(to, from)], onOrBefore: date)
        switch (forward, backward) {
        case let (f?, b?):
            // Prefer whichever was recorded closer to the requested date.
            return f.date >= b.date ? f.rate : invert(b.rate)
        case let (f?, nil):
            return f.rate
        case let (nil, b?):
            return invert(b.rate)
        case (nil, nil):
            if let f = table[Self.key(from, to)]?.first { return f.rate }
            if let b = table[Self.key(to, from)]?.first { return invert(b.rate) }
            return nil
        }
    }

    private func invert(_ rate: Decimal) -> Decimal? {
        guard rate != 0 else { return nil }
        return (Decimal(1) / rate).rounded(scale: 10)
    }

    /// Binary search for the last point with `date <= target`.
    private func latest(in points: [RatePoint]?, onOrBefore target: Date) -> RatePoint? {
        guard let points, !points.isEmpty else { return nil }
        var lo = 0, hi = points.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if points[mid].date <= target {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found.map { points[$0] }
    }
}
