import Foundation
import SwiftData

/// Gentle, in-app budget reminders. Each budget reminds at most once per level
/// (approaching / exceeded) per budget period, so users are never nagged.
@MainActor
enum BudgetNotifier {
    static func notice(after entry: LedgerEntry, context: ModelContext, now: Date = .now) -> ToastMessage? {
        guard AppSettings.budgetAlertsEnabled else { return nil }
        guard entry.kind == .expense || (entry.kind == .transfer && entry.fee > 0) else { return nil }
        let snap = LedgerSnapshot.load(from: context)
        guard !snap.budgets.isEmpty else { return nil }
        let base = AppSettings.baseCurrency
        let engine = BudgetEngine(finance: FinanceEngine(base: base, rates: snap.rates), monthStartDay: AppSettings.budgetStartDay)

        var touched = Set(entry.splitList.compactMap { $0.category?.id })
        if let id = entry.category?.id { touched.insert(id) }
        if let fee = UUID(uuidString: entry.feeCategoryIDRaw) { touched.insert(fee) }

        let relevant = snap.budgets.filter { b in
            if let c = b.categoryID { return touched.contains(c) }
            return touched.isEmpty || !touched.isSubset(of: b.excluded)
        }
        var candidates: [(budget: BudgetValue, status: BudgetStatus)] = []
        for budget in relevant {
            let status: BudgetStatus = engine.status(of: budget, entries: snap.entries, at: now)
            guard status.period.contains(entry.date), status.level != .normal else { continue }
            candidates.append((budget, status))
        }
        candidates.sort { a, b in
            if a.status.level != b.status.level { return a.status.level > b.status.level }
            return a.status.fraction > b.status.fraction
        }

        var notified = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.budgetNotified) ?? [])
        for candidate in candidates {
            let status = candidate.status
            let periodKey = String(Int(status.period.start.timeIntervalSince1970))
            let key = periodKey + "|" + status.budgetID.uuidString + "|" + String(status.level.rawValue)
            guard !notified.contains(key) else { continue }
            notified.insert(key)
            UserDefaults.standard.set(Array(notified.suffix(200)), forKey: SettingsKey.budgetNotified)
            var title = BudgetTitle.overall(candidate.budget.period)
            if let id = status.categoryID, let name = LedgerRepository(context: context).category(id: id)?.name {
                title = name
            }
            return message(for: status, title: title, base: base)
        }
        return nil
    }

    static func message(for status: BudgetStatus, title: String, base: String) -> ToastMessage {
        switch status.level {
        case .exceeded:
            let over = MoneyFormat.string(status.overspent, code: base)
            return ToastMessage(symbol: "exclamationmark.circle", text: String(localized: "\(title) is over budget by \(over)"), style: .warning)
        case .approaching, .normal:
            return ToastMessage(
                symbol: "gauge.with.dots.needle.67percent",
                text: String(localized: "\(title): \(MoneyFormat.percent(status.fraction)) of budget used"),
                style: .info
            )
        }
    }
}
