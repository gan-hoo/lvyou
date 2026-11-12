import Foundation

struct BudgetStatus: Identifiable {
    let id: UUID
    let budget: Budget
    let title: String
    let symbolName: String
    let colorHex: String
    /// Budget limit converted to the base currency.
    let limit: Decimal
    /// Amount spent in the period, in the base currency.
    let spent: Decimal
    let threshold: Double

    var remaining: Decimal { limit - spent }

    var fraction: Double {
        guard limit > 0 else { return spent > 0 ? 1 : 0 }
        return (spent / limit).doubleValue
    }

    var level: BudgetAlertLevel {
        if limit > 0 && spent > limit { return .exceeded }
        if fraction >= threshold { return .approaching }
        return .normal
    }
}

struct BudgetOverview {
    var overall: BudgetStatus?
    var categories: [BudgetStatus] = []

    var all: [BudgetStatus] { (overall.map { [$0] } ?? []) + categories }

    /// The most pressing status worth a gentle reminder.
    var mostUrgent: BudgetStatus? {
        all.filter { $0.level != .normal }.max { lhs, rhs in
            lhs.level == rhs.level ? lhs.fraction < rhs.fraction : lhs.level < rhs.level
        }
    }
}

struct BudgetEvaluator {
    let math: LedgerMath

    func overview(budgets: [Budget], entries: [LedgerEntry], period: Period) -> BudgetOverview {
        let expenses = entries.filter { $0.kind == .expense && period.contains($0.date) }
        var spentByCategory: [UUID: Decimal] = [:]
        var total: Decimal = 0
        for e in expenses {
            let v = math.value(e)
            total += v
            if let id = e.category?.id { spentByCategory[id, default: 0] += v }
        }

        var overview = BudgetOverview()
        for b in budgets {
            let limit = math.converter.convertOrSame(b.amount, from: b.currencyCode, to: math.base)
            if let category = b.category {
                overview.categories.append(BudgetStatus(
                    id: b.id,
                    budget: b,
                    title: category.name,
                    symbolName: category.symbolName,
                    colorHex: category.colorHex,
                    limit: limit,
                    spent: spentByCategory[category.id] ?? 0,
                    threshold: b.alertThreshold
                ))
            } else if overview.overall == nil {
                overview.overall = BudgetStatus(
                    id: b.id,
                    budget: b,
                    title: String(localized: "Monthly Budget"),
                    symbolName: "chart.pie",
                    colorHex: "4A7DFF",
                    limit: limit,
                    spent: total,
                    threshold: b.alertThreshold
                )
            }
        }
        overview.categories.sort { $0.fraction > $1.fraction }
        return overview
    }

    /// Daily spending allowance for the rest of the period.
    static func dailyAllowance(for status: BudgetStatus, period: Period) -> Decimal? {
        guard period.isCurrent else { return nil }
        let days = max(1, period.remainingDayCount + 1)
        guard status.remaining > 0 else { return 0 }
        return (status.remaining / Decimal(days)).rounded(scale: 2)
    }
}
