import SwiftUI

/// Compact native row for one entry.
/// `perspective` (an account ID) shows transfers as money in or out of that account.
struct TransactionRow: View {
    let entry: LedgerEntry
    var baseCurrency: String
    var engine: FinanceEngine
    var perspective: UUID? = nil
    var showsDate = false

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            SymbolBadge(symbol: entry.displaySymbol, colorHex: entry.displayColorHex, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if !entry.tagList.isEmpty {
                        Text(entry.tagList.map { "#" + $0.name }.joined(separator: " "))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DS.Colors.accent)
                            .lineLimit(1)
                    }
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(amountText)
                    .font(DS.Typography.rowAmount)
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                    .lineLimit(1)
                if let secondary = secondaryAmount {
                    Text(secondary.text)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(secondary.warning ? DS.Colors.warning : Color.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var isIncoming: Bool {
        entry.kind == .transfer && perspective != nil && entry.toAccount?.id == perspective
    }

    private var title: String {
        if entry.isRepayment { return String(localized: "Card Repayment") + " · " + (entry.toAccount?.name ?? "") }
        if entry.kind == .refund { return String(localized: "Refund") + " · " + (entry.category?.name ?? String(localized: "Uncategorized")) }
        if entry.isSplit { return String(localized: "Split") + " · " + entry.splitList.compactMap { $0.category?.name }.joined(separator: ", ") }
        return entry.displayTitle
    }

    private var subtitle: String {
        var parts: [String] = []
        if showsDate { parts.append(entry.date.text(.dateTime.month(.abbreviated).day())) }
        if !entry.payee.isEmpty { parts.append(entry.payee) }
        if !entry.note.isEmpty { parts.append(entry.note) }
        switch entry.kind {
        case .transfer:
            if entry.isRepayment, let from = entry.account?.name { parts.append(from) }
            if entry.fee > 0 { parts.append(String(localized: "Fee") + " " + MoneyFormat.string(entry.fee, code: entry.currencyCode)) }
        default:
            if let account = entry.account?.name { parts.append(account) }
        }
        parts.append(entry.date.timeText)
        return parts.joined(separator: " · ")
    }

    private var amountText: String {
        switch entry.kind {
        case .transfer:
            if isIncoming, let to = entry.toAccount {
                return MoneyFormat.string(entry.toAmount, code: to.currencyCode, showPlusSign: true)
            }
            if perspective != nil {
                return MoneyFormat.string(-(entry.amount + entry.fee), code: entry.currencyCode)
            }
            return MoneyFormat.string(entry.amount, code: entry.currencyCode)
        case .adjustment:
            return MoneyFormat.string(entry.adjustmentDelta, code: entry.currencyCode, showPlusSign: true)
        default:
            return MoneyFormat.signed(entry.amount, code: entry.currencyCode, kind: entry.kind)
        }
    }

    private var amountColor: Color {
        if entry.kind == .transfer && perspective != nil {
            return isIncoming ? DS.Colors.income : .primary
        }
        return DS.Colors.amount(for: entry.kind)
    }

    private var secondaryAmount: (text: String, warning: Bool)? {
        if entry.kind == .transfer {
            if let to = entry.toAccount, to.currencyCode != entry.currencyCode, !isIncoming {
                return ("→ " + MoneyFormat.string(entry.toAmount, code: to.currencyCode), false)
            }
            return nil
        }
        guard entry.kind != .adjustment, entry.currencyCode != baseCurrency else { return nil }
        if let value = engine.baseValue(EntryValue(entry)) {
            return ("≈ " + MoneyFormat.string(value, code: baseCurrency), false)
        }
        return (String(localized: "Pending conversion"), true)
    }
}
