import Foundation
import SwiftData

/// Books recurring plans once each occurrence is due (docs/FINANCE_RULES.md §6).
/// Future occurrences never touch balances; each entry carries the rule ID and the
/// occurrence day, so running this repeatedly never books the same occurrence twice.
@MainActor
struct RecurringService {
    let repository: LedgerRepository

    init(context: ModelContext) {
        repository = LedgerRepository(context: context)
    }

    struct Result: Equatable {
        var posted = 0
        var skippedDuplicates = 0
        var deactivated = 0
    }

    @discardableResult
    func postDueOccurrences(now: Date = .now) -> Result {
        var result = Result()
        let service = TransactionService(repository: repository)
        let cal = Calendar.ledger
        var booked = Set(repository.all(LedgerEntry.self).compactMap { e -> String? in
            guard !e.recurringRuleIDRaw.isEmpty, let day = e.occurrenceDate else { return nil }
            return e.recurringRuleIDRaw + "|" + String(Int(cal.startOfDay(for: day).timeIntervalSince1970))
        })

        for rule in repository.all(RecurringRule.self) where rule.isActive {
            let due = Recurrence.dueOccurrences(
                start: rule.startDate, frequency: rule.frequency, interval: rule.interval,
                fromIndex: rule.generatedCount, end: rule.endDate, now: now
            )
            for occurrence in due {
                let key = rule.id.uuidString + "|" + String(Int(cal.startOfDay(for: occurrence.date).timeIntervalSince1970))
                rule.generatedCount = occurrence.index + 1
                rule.nextDate = Recurrence.occurrence(rule.generatedCount, start: rule.startDate, frequency: rule.frequency, interval: rule.interval)
                if booked.contains(key) {
                    result.skippedDuplicates += 1
                    continue
                }
                guard let account = repository.account(id: rule.accountID) else {
                    rule.isActive = false
                    result.deactivated += 1
                    break
                }
                let draft = TransactionDraft(
                    kind: rule.kind,
                    amount: rule.amount,
                    date: occurrence.date,
                    note: rule.note.isEmpty ? rule.name : rule.note,
                    payee: rule.payee,
                    account: account,
                    toAccount: repository.account(id: rule.toAccountID),
                    toAmount: rule.toAmountRaw.isEmpty ? nil : DecimalCodec.decode(rule.toAmountRaw),
                    category: repository.category(id: rule.categoryID),
                    recurringRuleID: rule.id,
                    occurrenceDate: occurrence.date
                )
                do {
                    try service.save(draft)
                    booked.insert(key)
                    result.posted += 1
                } catch {
                    // An invalid plan (e.g. transfer target deleted) is paused, not retried forever.
                    rule.isActive = false
                    result.deactivated += 1
                    try? repository.commit()
                    break
                }
            }
            if let end = rule.endDate, rule.nextDate > end { rule.isActive = false }
        }
        try? repository.commit()
        return result
    }
}
