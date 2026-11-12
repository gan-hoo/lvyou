import Foundation

/// A calendar period (a month or a year) used by dashboard, statistics and budgets.
struct Period: Hashable, Sendable {
    enum Unit: String, CaseIterable, Identifiable, Sendable {
        case month
        case year

        var id: String { rawValue }

        var title: String {
            switch self {
            case .month: String(localized: "Month")
            case .year: String(localized: "Year")
            }
        }

        var component: Calendar.Component {
            switch self {
            case .month: .month
            case .year: .year
            }
        }
    }

    let unit: Unit
    let start: Date
    let end: Date

    init(unit: Unit, containing date: Date, calendar: Calendar = .current) {
        self.unit = unit
        let interval = calendar.dateInterval(of: unit.component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
        self.start = interval.start
        self.end = interval.end
    }

    static func month(_ date: Date = .now) -> Period { Period(unit: .month, containing: date) }
    static func year(_ date: Date = .now) -> Period { Period(unit: .year, containing: date) }

    func shifted(by value: Int, calendar: Calendar = .current) -> Period {
        let date = calendar.date(byAdding: unit.component, value: value, to: start) ?? start
        return Period(unit: unit, containing: date, calendar: calendar)
    }

    var previous: Period { shifted(by: -1) }
    var next: Period { shifted(by: 1) }

    func contains(_ date: Date) -> Bool { date >= start && date < end }

    var isCurrent: Bool { contains(.now) }

    var isFuture: Bool { start > .now }

    var title: String {
        switch unit {
        case .month: start.monthTitle
        case .year: start.yearTitle
        }
    }

    /// Number of days in the period.
    var dayCount: Int {
        max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1)
    }

    /// Days elapsed so far (inclusive of today) — used for daily averages.
    var elapsedDayCount: Int {
        if end <= .now { return dayCount }
        if start > .now { return 0 }
        let days = Calendar.current.dateComponents([.day], from: start, to: Calendar.current.startOfDay(for: .now)).day ?? 0
        return min(dayCount, days + 1)
    }

    var remainingDayCount: Int { max(0, dayCount - elapsedDayCount) }

    /// End of the comparable span in `other` (usually the previous period): for a
    /// period still in progress, only as much of `other` as has elapsed in `self`,
    /// so "vs. last month" compares like with like.
    func comparableEnd(in other: Period, now: Date = .now) -> Date {
        guard contains(now) else { return other.end }
        let elapsed = now.timeIntervalSince(start)
        return min(other.end, other.start.addingTimeInterval(elapsed))
    }

    /// Months contained in a yearly period (or the month itself).
    var months: [Period] {
        switch unit {
        case .month: return [self]
        case .year: return (0..<12).map { Period.month(Calendar.current.date(byAdding: .month, value: $0, to: start) ?? start) }
        }
    }

    /// Start-of-day dates for every day of the period.
    var days: [Date] {
        (0..<dayCount).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }
}

extension Calendar {
    func isSameDay(_ a: Date, _ b: Date) -> Bool { isDate(a, inSameDayAs: b) }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    /// Keeps the calendar day of `self` but takes the time-of-day from `time`.
    func combining(timeOf time: Date) -> Date {
        let cal = Calendar.current
        let day = cal.dateComponents([.year, .month, .day], from: self)
        let t = cal.dateComponents([.hour, .minute, .second], from: time)
        var c = DateComponents()
        c.year = day.year; c.month = day.month; c.day = day.day
        c.hour = t.hour; c.minute = t.minute; c.second = t.second
        return cal.date(from: c) ?? self
    }
}
