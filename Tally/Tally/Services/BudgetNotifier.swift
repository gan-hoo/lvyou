import Foundation
import SwiftData

/// Gentle, in-app budget reminders. Each budget can remind at most once per
/// level (approaching / exceeded) per month, so users are never nagged.
@MainActor
enum BudgetNotifier {
    static func notice(after entry: LedgerEntry, budgets: [Budget], context: ModelContext, now: Date = .now) -> ToastMessage? {
        guard AppSettings.budgetAlertsEnabled, entry.kind == .expense, !budgets.isEmpty else { return nil }
        let period = Period.month(entry.date)
        guard period.contains(now) else { return nil }

        let start = period.start, end = period.end
        let descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        let entries = (try? context.fetch(descriptor)) ?? []
        let rates = (try? context.fetch(FetchDescriptor<ExchangeRate>())) ?? []
        let math = LedgerMath(base: AppSettings.baseCurrency, rates: rates)
        let overview = BudgetEvaluator(math: math).overview(budgets: budgets, entries: entries, period: period)

        var candidates: [BudgetStatus] = []
        if let id = entry.category?.id, let status = overview.categories.first(where: { $0.budget.category?.id == id }) {
            candidates.append(status)
        }
        if let overall = overview.overall { candidates.append(overall) }

        let monthKey = period.start.formatted(.iso8601.year().month())
        var notified = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.budgetNotified) ?? [])

        for status in candidates.sorted(by: { $0.level > $1.level }) where status.level != .normal {
            let key = "\(monthKey)|\(status.id.uuidString)|\(status.level.rawValue)"
            guard !notified.contains(key) else { continue }
            notified.insert(key)
            // Keep the stored set small: only the current month matters.
            let pruned = notified.filter { $0.hasPrefix(monthKey) }
            UserDefaults.standard.set(Array(pruned), forKey: SettingsKey.budgetNotified)
            return message(for: status, base: math.base)
        }
        return nil
    }

    static func message(for status: BudgetStatus, base: String) -> ToastMessage {
        switch status.level {
        case .exceeded:
            let over = MoneyFormat.string(-status.remaining, code: base)
            return ToastMessage(
                symbol: "exclamationmark.circle",
                text: String(localized: "\(status.title) is over budget by \(over)"),
                style: .warning
            )
        case .approaching, .normal:
            return ToastMessage(
                symbol: "gauge.with.dots.needle.67percent",
                text: String(localized: "\(status.title): \(MoneyFormat.percent(status.fraction)) of budget used"),
                style: .info
            )
        }
    }
}
