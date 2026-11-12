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
        let statuses = relevant
            .map { engine.status(of: $0, entries: snap.entries, at: now) }
            .filter { $0.period.contains(entry.date) && $0.level != .normal }
            .sorted { $0.level == $1.level ? $0.fraction > $1.fraction : $0.level > $1.level }

        var notified = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.budgetNotified) ?? [])
        for status in statuses {
            let periodKey = String(Int(status.period.start.timeIntervalSince1970))
            let key = "\(periodKey)|\(status.budgetID.uuidString)|\(status.level.rawValue)"
            guard !notified.contains(key) else { continue }
            notified.insert(key)
            UserDefaults.standard.set(Array(notified.suffix(200)), forKey: SettingsKey.budgetNotified)
            let title = status.categoryID
                .flatMap { id in LedgerRepository(context: context).category(id: id)?.name }
                ?? String(localized: "Monthly Budget")
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
