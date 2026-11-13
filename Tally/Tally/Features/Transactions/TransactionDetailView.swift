import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    let entry: LedgerEntry

    @Environment(AppRouter.self) private var router
    @Environment(LedgerCache.self) private var cache
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase

    var body: some View {
        if entry.isDeleted || entry.modelContext == nil {
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }

    private var original: LedgerEntry? {
        LedgerRepository(context: context).entry(id: UUID(uuidString: entry.refundOfIDRaw))
    }

    private var refunds: [LedgerEntry] {
        let id = entry.id.uuidString
        return LedgerRepository(context: context).all(LedgerEntry.self).filter { $0.refundOfIDRaw == id }
    }

    private var content: some View {
        let engine = cache.engine(base: baseCurrency)
        let value = entry.kind == .expense
            ? engine.baseValue(entry.paidAmount, of: EntryValue(entry))
            : engine.baseValue(EntryValue(entry))
        return List {
            Section {
                VStack(spacing: DS.Spacing.m) {
                    SymbolBadge(symbol: entry.displaySymbol, colorHex: entry.displayColorHex, size: 56, style: .solid)
                    Text(entry.kind == .transfer ? entry.displayTitle : entry.kind.title + " · " + entry.displayTitle)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(entry.kind == .adjustment
                         ? MoneyFormat.string(entry.adjustmentDelta, code: entry.currencyCode, showPlusSign: true)
                         : MoneyFormat.signed(entry.paidAmount, code: entry.currencyCode, kind: entry.kind))
                        .font(DS.Typography.heroAmount)
                        .monospacedDigit()
                        .foregroundStyle(DS.Colors.amount(for: entry.kind))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if entry.currencyCode != baseCurrency && entry.kind != .transfer && entry.kind != .adjustment {
                        if let value {
                            Text(verbatim: "≈ " + MoneyFormat.string(value, code: baseCurrency))
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        } else {
                            Text("Pending conversion").font(.subheadline).foregroundStyle(DS.Colors.warning)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.m)
                .listRowBackground(Color.clear)
            }

            Section {
                switch entry.kind {
                case .transfer:
                    accountLink("From", entry.account)
                    accountLink("To", entry.toAccount)
                    if let to = entry.toAccount, to.currencyCode != entry.currencyCode {
                        LabeledContent("Received", value: MoneyFormat.string(entry.toAmount, code: to.currencyCode))
                        if entry.amount > 0 {
                            let rate = (entry.toAmount / entry.amount).rounded(scale: 6)
                            LabeledContent("Rate", value: "1 \(entry.currencyCode) = \(MoneyFormat.rate(rate)) \(to.currencyCode)")
                        }
                    }
                    if entry.fee > 0 {
                        LabeledContent("Fee", value: MoneyFormat.string(entry.fee, code: entry.currencyCode))
                    }
                    if entry.isRepayment {
                        Text("Repayment: reduces the amount owed; not counted as spending.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                case .adjustment:
                    accountLink("Account", entry.account)
                    if !entry.adjustmentPreviousBalanceRaw.isEmpty {
                        let previous = DecimalCodec.decode(entry.adjustmentPreviousBalanceRaw)
                        LabeledContent("Balance Before", value: MoneyFormat.string(previous, code: entry.currencyCode))
                        LabeledContent("Balance After", value: MoneyFormat.string(previous + entry.adjustmentDelta, code: entry.currencyCode))
                    }
                    Text("Adjustments change only the account balance and are excluded from income and spending.")
                        .font(.footnote).foregroundStyle(.secondary)
                default:
                    if !entry.isSplit {
                        LabeledContent("Category", value: entry.category?.name ?? String(localized: "Uncategorized"))
                    }
                    accountLink("Account", entry.account)
                    if entry.kind == .expense && (entry.discount > 0 || entry.fee > 0) {
                        LabeledContent("Price", value: MoneyFormat.string(entry.amount, code: entry.currencyCode))
                        if entry.discount > 0 {
                            LabeledContent("Discount", value: MoneyFormat.string(-entry.discount, code: entry.currencyCode))
                        }
                        if entry.fee > 0 {
                            LabeledContent("Fee", value: MoneyFormat.string(entry.fee, code: entry.currencyCode, showPlusSign: true))
                        }
                        LabeledContent("Paid", value: MoneyFormat.string(entry.paidAmount, code: entry.currencyCode))
                            .fontWeight(.semibold)
                        Text("The discount lowers the spending in this purchase's categories; the fee is counted under Fees.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !entry.payee.isEmpty {
                    LabeledContent("Payee", value: entry.payee)
                }
                LabeledContent("Date", value: entry.date.text(date: .long, time: .shortened))
                if !entry.tagList.isEmpty {
                    LabeledContent("Tags", value: entry.tagList.map { "#" + $0.name }.joined(separator: " "))
                }
            }

            if entry.isSplit {
                Section("Split") {
                    ForEach(entry.splitList) { split in
                        HStack(spacing: DS.Spacing.m) {
                            SymbolBadge(symbol: split.category?.symbolName ?? "questionmark", colorHex: split.category?.colorHex ?? "8E8E93", size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(split.category?.name ?? String(localized: "Uncategorized"))
                                if !split.note.isEmpty { Text(split.note).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(MoneyFormat.string(split.amount, code: entry.currencyCode)).monospacedDigit()
                        }
                    }
                }
            }

            if entry.kind == .refund, let original {
                Section("Refund Of") {
                    NavigationLink(value: original) {
                        TransactionRow(entry: original, baseCurrency: baseCurrency, engine: engine, showsDate: true)
                    }
                }
            }
            if !refunds.isEmpty {
                Section("Refunds") {
                    ForEach(refunds) { r in
                        NavigationLink(value: r) {
                            TransactionRow(entry: r, baseCurrency: baseCurrency, engine: engine, showsDate: true)
                        }
                    }
                }
            }

            if !entry.note.isEmpty {
                Section("Note") { Text(entry.note).textSelection(.enabled) }
            }

            if entry.kind != .adjustment {
                Section {
                    LabeledContent("Original amount", value: MoneyFormat.string(entry.amount, code: entry.currencyCode))
                    if entry.hasSnapshot {
                        LabeledContent("Recorded rate", value: "1 \(entry.currencyCode) = \(MoneyFormat.rate(entry.rateToBase)) \(entry.baseCurrencyCode)")
                        LabeledContent("Converted at entry", value: MoneyFormat.string(entry.baseAmount, code: entry.baseCurrencyCode))
                    } else {
                        LabeledContent("Recorded rate", value: String(localized: "Pending conversion"))
                    }
                } header: {
                    Text("Currency")
                } footer: {
                    Text("Reports use the rate saved with the transaction. If the main currency changes, the historical rate for the transaction date is used; without one the amount is shown as pending — never converted 1:1.")
                }
            }

            Section {
                if entry.kind != .adjustment {
                    Button { router.edit(entry) } label: { Label("Edit", systemImage: "pencil") }
                    Button { duplicate() } label: { Label("Duplicate as Today", systemImage: "plus.square.on.square") }
                }
                if entry.kind == .expense {
                    Button { router.refund(entry) } label: { Label("Record Refund", systemImage: "arrow.uturn.backward") }
                }
                Button(role: .destructive) {
                    let target = entry
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        TrashActions.moveToTrash([target], context: context, toasts: toasts)
                    }
                } label: { Label("Delete", systemImage: "trash") }
            } footer: {
                Text("Created \(entry.createdAt.text(date: .abbreviated, time: .shortened)) · Updated \(entry.updatedAt.text(date: .abbreviated, time: .shortened))")
            }
        }
        .listStyle(.insetGrouped)
        .pageBackground()
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if entry.kind != .adjustment {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { router.edit(entry) }
                }
            }
        }
    }

    @ViewBuilder
    private func accountLink(_ title: LocalizedStringKey, _ account: Account?) -> some View {
        if let account {
            NavigationLink(value: account) {
                LabeledContent(title, value: account.name)
            }
        } else {
            LabeledContent(title, value: "—")
        }
    }

    private func duplicate() {
        do {
            try TransactionService(context: context).duplicate(entry)
            Haptics.success()
            toasts.show(ToastMessage(symbol: "plus.square.on.square", text: String(localized: "Duplicated to today"), style: .success))
        } catch {
            toasts.show(ToastMessage(symbol: "exclamationmark.triangle", text: error.localizedDescription, style: .warning))
        }
    }
}
