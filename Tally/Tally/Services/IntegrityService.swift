import Foundation
import SwiftData

/// Consistency checks over the ledger (Settings › Data › Integrity Check).
@MainActor
struct IntegrityService {
    struct Issue: Identifiable, Equatable {
        enum Kind: String {
            case splitMismatch, transferWithoutDestination, transferToSelf, missingAccount
            case invalidAmount, pendingConversion, orphanRule
        }
        let id = UUID()
        let kind: Kind
        let entryID: UUID?
        let detail: String

        var title: String {
            switch kind {
            case .splitMismatch: String(localized: "Split amounts don't add up")
            case .transferWithoutDestination: String(localized: "Transfer without destination")
            case .transferToSelf: String(localized: "Transfer to the same account")
            case .missingAccount: String(localized: "Transaction without account")
            case .invalidAmount: String(localized: "Invalid amount")
            case .pendingConversion: String(localized: "Waiting for an exchange rate")
            case .orphanRule: String(localized: "Recurring plan uses a deleted account")
            }
        }
    }

    struct Report: Equatable {
        var checkedEntries = 0
        var issues: [Issue] = []
        var isHealthy: Bool { issues.isEmpty }
    }

    let repository: LedgerRepository

    init(context: ModelContext) {
        repository = LedgerRepository(context: context)
    }

    func run(base: String = AppSettings.baseCurrency) -> Report {
        var report = Report()
        let entries = repository.all(LedgerEntry.self)
        let accountIDs = Set(repository.all(Account.self).map(\.id))
        report.checkedEntries = entries.count
        let converter = repository.converter()
        for e in entries {
            let label = "\(e.date.shortDateText) · \(e.displayTitle) · \(DecimalCodec.encode(e.amount)) \(e.currencyCode)"
            if e.account == nil {
                report.issues.append(Issue(kind: .missingAccount, entryID: e.id, detail: label))
            }
            if e.kind != .adjustment && e.amount <= 0 {
                report.issues.append(Issue(kind: .invalidAmount, entryID: e.id, detail: label))
            }
            if e.kind == .transfer {
                if e.toAccount == nil {
                    report.issues.append(Issue(kind: .transferWithoutDestination, entryID: e.id, detail: label))
                } else if e.toAccount?.id == e.account?.id {
                    report.issues.append(Issue(kind: .transferToSelf, entryID: e.id, detail: label))
                }
            }
            if e.isSplit {
                let digits = CurrencyInfo.info(for: e.currencyCode).fractionDigits
                let total = e.splitList.sum { $0.amount }.rounded(scale: digits)
                if total != e.amount.rounded(scale: digits) {
                    report.issues.append(Issue(kind: .splitMismatch, entryID: e.id, detail: label))
                }
            }
            if e.kind != .adjustment && e.currencyCode != base && !(e.hasSnapshot && e.baseCurrencyCode == base) {
                if converter.rate(from: e.currencyCode, to: base, on: e.date) == nil {
                    report.issues.append(Issue(kind: .pendingConversion, entryID: e.id, detail: label))
                }
            }
        }
        for rule in repository.all(RecurringRule.self) where rule.isActive {
            if let id = rule.accountID, !accountIDs.contains(id) {
                report.issues.append(Issue(kind: .orphanRule, entryID: nil, detail: rule.name))
            }
        }
        return report
    }

    /// Fixes what can be fixed safely: fills in exchange-rate snapshots now that rates
    /// exist, and pauses recurring plans whose account is gone. Returns items fixed.
    @discardableResult
    func repair(base: String = AppSettings.baseCurrency) -> Int {
        var fixed = TransactionService(repository: repository).refreshPendingSnapshots(base: base)
        let accountIDs = Set(repository.all(Account.self).map(\.id))
        for rule in repository.all(RecurringRule.self) where rule.isActive {
            if let id = rule.accountID, !accountIDs.contains(id) {
                rule.isActive = false
                fixed += 1
            }
        }
        try? repository.commit()
        return fixed
    }
}
