import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    let entry: LedgerEntry

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @Query private var rates: [ExchangeRate]
    @State private var confirmDelete = false

    var body: some View {
        if entry.isDeleted || entry.modelContext == nil {
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }

    private var content: some View {
        let math = LedgerMath(base: baseCurrency, rates: rates)
        return List {
            Section {
                VStack(spacing: DS.Spacing.m) {
                    SymbolBadge(symbol: entry.displaySymbol, colorHex: entry.displayColorHex, size: 56, style: .solid)
                    Text(entry.displayTitle)
                        .font(.headline)
                    Text(MoneyFormat.signed(entry.amount, code: entry.currencyCode, kind: entry.kind))
                        .font(DS.Typography.heroAmount)
                        .monospacedDigit()
                        .foregroundStyle(DS.Colors.amount(for: entry.kind))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if entry.currencyCode != baseCurrency && entry.kind != .transfer {
                        Text(verbatim: "≈ " + MoneyFormat.string(math.value(entry), code: baseCurrency))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.m)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Type", value: entry.kind.title)
                if entry.kind == .transfer {
                    LabeledContent("From", value: entry.account?.name ?? "—")
                    LabeledContent("To", value: entry.toAccount?.name ?? "—")
                    if let to = entry.toAccount, to.currencyCode != entry.currencyCode {
                        LabeledContent("Credited", value: MoneyFormat.string(entry.toAmount, code: to.currencyCode))
                    }
                } else {
                    LabeledContent("Category", value: entry.category?.name ?? String(localized: "Uncategorized"))
                    if let account = entry.account {
                        NavigationLink(value: account) {
                            LabeledContent("Account", value: account.name)
                        }
                    }
                }
                LabeledContent("Date", value: entry.date.formatted(date: .long, time: .shortened))
                if !entry.tagList.isEmpty {
                    LabeledContent("Tags", value: entry.tagList.map { "#" + $0.name }.joined(separator: " "))
                }
            }

            if !entry.note.isEmpty {
                Section("Note") {
                    Text(entry.note).textSelection(.enabled)
                }
            }

            Section {
                LabeledContent("Original amount", value: MoneyFormat.string(entry.amount, code: entry.currencyCode))
                LabeledContent("Recorded rate", value: "1 \(entry.currencyCode) = \(MoneyFormat.rate(entry.rateToBase)) \(entry.baseCurrencyCode)")
                LabeledContent("Converted at entry", value: MoneyFormat.string(entry.baseAmount, code: entry.baseCurrencyCode))
            } header: {
                Text("Currency")
            } footer: {
                Text("The rate in effect on the transaction date is stored with the record, so later rate changes never alter history.")
            }

            Section {
                Button {
                    router.edit(entry)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button {
                    if LedgerStore(context: context).duplicate(entry) != nil {
                        Haptics.success()
                        toasts.show(ToastMessage(symbol: "plus.square.on.square", text: String(localized: "Duplicated to today"), style: .success))
                    }
                } label: {
                    Label("Duplicate as Today", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } footer: {
                Text("Created \(entry.createdAt.formatted(date: .abbreviated, time: .shortened)) · Updated \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { router.edit(entry) }
            }
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let target = entry
                let store = LedgerStore(context: context)
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    store.delete(target)
                    Haptics.success()
                }
            }
        } message: {
            Text("This can't be undone.")
        }
    }
}
