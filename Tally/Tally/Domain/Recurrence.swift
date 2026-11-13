import Foundation

/// Occurrence dates for recurring rules. Occurrence *n* is always computed from the
/// start date (start + n × interval) so month ends never drift (31 Jan → 28 Feb → 31 Mar).
enum Recurrence {
    static func occurrence(_ index: Int, start: Date, frequency: RecurrenceFrequency, interval: Int, calendar: Calendar = .ledger) -> Date {
        calendar.date(byAdding: frequency.component, value: index * max(1, interval), to: start) ?? start
    }

    /// Every occurrence from `fromIndex` that is due on or before `now` (and not after `end`).
    static func dueOccurrences(
        start: Date,
        frequency: RecurrenceFrequency,
        interval: Int,
        fromIndex: Int,
        end: Date?,
        now: Date = .now,
        limit: Int = 400
    ) -> [(index: Int, date: Date)] {
        var result: [(Int, Date)] = []
        var i = fromIndex
        while result.count < limit {
            let d = occurrence(i, start: start, frequency: frequency, interval: interval)
            if d > now { break }
            if let end, d > end { break }
            result.append((i, d))
            i += 1
        }
        return result.map { (index: $0.0, date: $0.1) }
    }
}
