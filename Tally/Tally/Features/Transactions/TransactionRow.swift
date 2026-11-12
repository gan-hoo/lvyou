import SwiftUI

/// Compact, native-feeling row used by the dashboard, the transaction list and detail screens.
struct TransactionRow: View {
    let entry: LedgerEntry
    var baseCurrency: String
    var baseValue: Decimal?
    var showsDate = false

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            SymbolBadge(symbol: entry.displaySymbol, colorHex: entry.displayColorHex, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.displayTitle)
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
                Text(MoneyFormat.signed(entry.amount, code: entry.currencyCode, kind: entry.kind))
                    .font(DS.Typography.rowAmount)
                    .monospacedDigit()
                    .foregroundStyle(DS.Colors.amount(for: entry.kind))
                    .lineLimit(1)
                if entry.currencyCode != baseCurrency, let baseValue, entry.kind != .transfer {
                    Text(verbatim: "≈ " + MoneyFormat.string(baseValue, code: baseCurrency))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if entry.kind == .transfer, let to = entry.toAccount, to.currencyCode != entry.currencyCode {
                    Text(verbatim: "→ " + MoneyFormat.string(entry.toAmount, code: to.currencyCode))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        if showsDate { parts.append(entry.date.formatted(.dateTime.month(.abbreviated).day())) }
        if !entry.note.isEmpty { parts.append(entry.note) }
        if entry.kind != .transfer, let account = entry.account?.name { parts.append(account) }
        if !showsDate || parts.count < 2 { parts.append(entry.date.timeText) }
        return parts.joined(separator: " · ")
    }
}
