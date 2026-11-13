import Foundation

extension Calendar {
    /// Gregorian calendar in the user's time zone with weeks starting on Monday.
    static var ledger: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = AppLocale.current
        cal.timeZone = .current
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    func isSameDay(_ a: Date, _ b: Date) -> Bool { isDate(a, inSameDayAs: b) }
}

/// A reporting period: a week, month, year or custom range of whole days.
struct Period: Hashable, Sendable {
    enum Unit: String, CaseIterable, Identifiable, Sendable {
        case week
        case month
        case year
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: String(localized: "Week")
            case .month: String(localized: "Month")
            case .year: String(localized: "Year")
            case .custom: String(localized: "Custom")
            }
        }
    }

    let unit: Unit
    let start: Date
    let end: Date

    init(unit: Unit, containing date: Date, calendar: Calendar = .ledger) {
        self.unit = unit
        let component: Calendar.Component
        switch unit {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year, .custom: component = .year
        }
        let interval = calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
        self.start = interval.start
        self.end = interval.end
    }

    /// Custom range covering whole days from `start` through `end` (inclusive).
    init(customFrom start: Date, through end: Date, calendar: Calendar = .ledger) {
        self.unit = .custom
        let s = calendar.startOfDay(for: min(start, end))
        let e = calendar.startOfDay(for: max(start, end))
        self.start = s
        self.end = calendar.date(byAdding: .day, value: 1, to: e) ?? e.addingTimeInterval(86_400)
    }

    private init(unit: Unit, start: Date, end: Date) {
        self.unit = unit
        self.start = start
        self.end = end
    }

    static func week(_ date: Date = .now) -> Period { Period(unit: .week, containing: date) }
    static func month(_ date: Date = .now) -> Period { Period(unit: .month, containing: date) }
    static func year(_ date: Date = .now) -> Period { Period(unit: .year, containing: date) }

    func shifted(by value: Int, calendar: Calendar = .ledger) -> Period {
        switch unit {
        case .week:
            return Period(unit: .week, containing: calendar.date(byAdding: .weekOfYear, value: value, to: start) ?? start)
        case .month:
            return Period(unit: .month, containing: calendar.date(byAdding: .month, value: value, to: start) ?? start)
        case .year:
            return Period(unit: .year, containing: calendar.date(byAdding: .year, value: value, to: start) ?? start)
        case .custom:
            let days = dayCount * value
            let s = calendar.date(byAdding: .day, value: days, to: start) ?? start
            let e = calendar.date(byAdding: .day, value: days, to: end) ?? end
            return Period(unit: .custom, start: s, end: e)
        }
    }

    var previous: Period { shifted(by: -1) }
    var next: Period { shifted(by: 1) }

    func contains(_ date: Date) -> Bool { date >= start && date < end }

    var isCurrent: Bool { contains(.now) }

    var isFuture: Bool { start > .now }

    var interval: DateInterval { DateInterval(start: start, end: end) }

    var title: String {
        switch unit {
        case .month: return start.monthTitle
        case .year: return start.yearTitle
        case .week, .custom:
            return Date.rangeText(start, end.addingTimeInterval(-1))
        }
    }

    /// Number of days in the period.
    var dayCount: Int {
        max(1, Calendar.ledger.dateComponents([.day], from: start, to: end).day ?? 1)
    }

    /// Days elapsed so far (inclusive of today).
    var elapsedDayCount: Int {
        if end <= .now { return dayCount }
        if start > .now { return 0 }
        let days = Calendar.ledger.dateComponents([.day], from: start, to: Calendar.ledger.startOfDay(for: .now)).day ?? 0
        return min(dayCount, days + 1)
    }

    /// Days left including today.
    var remainingDayCount: Int {
        if end <= .now { return 0 }
        if start > .now { return dayCount }
        return max(1, dayCount - elapsedDayCount + 1)
    }

    /// Calendar months overlapping the period.
    var months: [Period] {
        var result: [Period] = []
        var cursor = Period.month(start)
        while cursor.start < end && result.count < 240 {
            result.append(cursor)
            cursor = cursor.next
        }
        return result
    }

    /// Start-of-day dates for every day of the period.
    var days: [Date] {
        (0..<min(dayCount, 3_700)).compactMap { Calendar.ledger.date(byAdding: .day, value: $0, to: start) }
    }

    /// End of the comparable span in `other`: for a period still in progress, only
    /// as much of `other` as has elapsed in `self`, so comparisons are like with like.
    func comparableEnd(in other: Period, now: Date = .now) -> Date {
        guard contains(now) else { return other.end }
        let elapsed = now.timeIntervalSince(start)
        return min(other.end, other.start.addingTimeInterval(elapsed))
    }
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
