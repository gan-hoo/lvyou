import Foundation

struct BudgetStatus: Identifiable, Equatable, Sendable {
    var id: UUID { budgetID }
    let budgetID: UUID
    let categoryID: UUID?
    let period: DateInterval
    /// Base amount for the period (converted to the base currency).
    let baseLimit: Decimal
    /// Leftover (positive) or overspending (negative) carried from earlier periods.
    let carried: Decimal
    /// Net spending counted against the budget.
    let spent: Decimal
    let threshold: Double
    /// Days left in the period, including today (0 for past periods).
    let daysRemaining: Int
    /// Entries left out because they need a missing exchange rate.
    let pendingCount: Int
    /// True when the budget amount itself cannot be converted to the base currency.
    let limitPending: Bool

    var limit: Decimal { baseLimit + carried }
    var remaining: Decimal { limit - spent }
    var overspent: Decimal { max(0, spent - limit) }

    var fraction: Double {
        guard limit > 0 else { return spent > 0 ? 1 : 0 }
        return (spent / limit).doubleValue
    }

    var level: BudgetAlertLevel {
        if spent > limit { return .exceeded }
        if limit > 0 && fraction >= threshold { return .approaching }
        return .normal
    }

    /// Suggested spending per remaining day, nil when over budget or the period is over.
    var dailyAllowance: Decimal? {
        guard daysRemaining > 0, remaining > 0 else { return nil }
        return (remaining / Decimal(daysRemaining)).rounded(scale: 2, mode: .down)
    }
}

/// Budget periods and progress. Implements docs/FINANCE_RULES.md §5.
struct BudgetEngine: Sendable {
    let finance: FinanceEngine
    /// First day of a monthly budget period (1…28).
    let monthStartDay: Int

    init(finance: FinanceEngine, monthStartDay: Int = 1) {
        self.finance = finance
        self.monthStartDay = min(28, max(1, monthStartDay))
    }

    private var calendar: Calendar { .ledger }

    /// The budget period that contains `date`.
    func period(of budget: BudgetValue, containing date: Date) -> DateInterval {
        let cal = calendar
        switch budget.period {
        case .monthly:
            let day = cal.component(.day, from: date)
            var comps = cal.dateComponents([.year, .month], from: date)
            comps.day = monthStartDay
            var start = cal.date(from: comps) ?? cal.startOfDay(for: date)
            if day < monthStartDay {
                start = cal.date(byAdding: .month, value: -1, to: start) ?? start
            }
            let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .weekly:
            return cal.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: cal.startOfDay(for: date), duration: 7 * 86_400)
        case .yearly:
            return cal.dateInterval(of: .year, for: date) ?? DateInterval(start: cal.startOfDay(for: date), duration: 365 * 86_400)
        case .custom:
            let length = max(1, budget.customLengthDays)
            let anchor = cal.startOfDay(for: budget.anchorDate)
            let days = cal.dateComponents([.day], from: anchor, to: cal.startOfDay(for: date)).day ?? 0
            let index = Int((Double(days) / Double(length)).rounded(.down))
            let start = cal.date(byAdding: .day, value: index * length, to: anchor) ?? anchor
            let end = cal.date(byAdding: .day, value: length, to: start) ?? start
            return DateInterval(start: start, end: end)
        }
    }

    func previousPeriod(of budget: BudgetValue, before interval: DateInterval) -> DateInterval {
        period(of: budget, containing: interval.start.addingTimeInterval(-1))
    }

    /// Net spending counted against `budget` in `interval`, plus pending count.
    func spent(_ budget: BudgetValue, entries: [EntryValue], in interval: DateInterval) -> (Decimal, Int) {
        var total: Decimal = 0
        var pending = 0
        for e in entries where e.date >= interval.start && e.date < interval.end {
            guard let parts = finance.expenseContributions(e) else {
                if e.kind == .expense || e.kind == .refund || e.fee > 0 { pending += 1 }
                continue
            }
            for p in parts {
                if let category = budget.categoryID {
                    if p.categoryID == category { total += p.amount }
                } else if let id = p.categoryID, budget.excluded.contains(id) {
                    continue
                } else {
                    total += p.amount
                }
            }
        }
        return (total, pending)
    }

    func status(of budget: BudgetValue, entries: [EntryValue], at date: Date = .now) -> BudgetStatus {
        let interval = period(of: budget, containing: date)
        let converted = finance.converter.convert(budget.amount, from: budget.currency, to: finance.base, on: date)
        let baseLimit = converted ?? 0
        let (spent, pending) = spent(budget, entries: entries, in: interval)

        var carried: Decimal = 0
        if budget.rollover, converted != nil {
            // Walk forward from the period the budget started in.
            var periods: [DateInterval] = []
            var cursor = previousPeriod(of: budget, before: interval)
            let firstStart = period(of: budget, containing: budget.createdAt).start
            while cursor.start >= firstStart && periods.count < 36 {
                periods.append(cursor)
                cursor = previousPeriod(of: budget, before: cursor)
            }
            for p in periods.reversed() {
                let (s, _) = self.spent(budget, entries: entries, in: p)
                carried = baseLimit + carried - s
            }
        }

        let now = Date.now
        let daysRemaining: Int
        if interval.end <= now {
            daysRemaining = 0
        } else if interval.start > now {
            daysRemaining = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        } else {
            let today = calendar.startOfDay(for: now)
            daysRemaining = max(1, calendar.dateComponents([.day], from: today, to: interval.end).day ?? 1)
        }

        return BudgetStatus(
            budgetID: budget.id,
            categoryID: budget.categoryID,
            period: interval,
            baseLimit: baseLimit,
            carried: carried,
            spent: spent,
            threshold: budget.threshold,
            daysRemaining: daysRemaining,
            pendingCount: pending,
            limitPending: converted == nil
        )
    }
}
