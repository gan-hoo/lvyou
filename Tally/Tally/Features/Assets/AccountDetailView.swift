import SwiftUI
import SwiftData

struct AccountDetailView: View {
    let account: Account

    @Environment(AppRouter.self) private var router
    @Environment(LedgerCache.self) private var cache
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @State private var showEditor = false
    @State private var showReconcile = false
    @State private var visibleCount = 100

    var body: some View {
        if account.isDeleted || account.modelContext == nil {
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }

    private var related: [LedgerEntry] {
        let id = account.id
        return entries.filter { $0.account?.id == id || $0.toAccount?.id == id }
    }

    private var content: some View {
        let balance = cache.balance(of: account.id)
        let list = related
        let engine = cache.engine(base: baseCurrency)
        return List {
            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    HStack(spacing: DS.Spacing.m) {
                        SymbolBadge(symbol: account.symbolName, colorHex: account.colorHex, size: 44, style: .solid)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name).font(.headline)
                            Text(verbatim: account.kind.title + " · " + account.currencyCode
                                 + (account.groupName.isEmpty ? "" : " · " + account.groupName))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if account.kind.isLiability && balance <= 0 {
                            Text("Amount Owed").font(.subheadline).foregroundStyle(.secondary)
                            AmountText(value: -balance, code: account.currencyCode, font: DS.Typography.heroAmount,
                                       color: balance < 0 ? DS.Colors.danger : .primary)
                        } else {
                            Text("Current Balance").font(.subheadline).foregroundStyle(.secondary)
                            AmountText(value: balance, code: account.currencyCode, font: DS.Typography.heroAmount,
                                       color: balance < 0 ? DS.Colors.danger : .primary)
                        }
                        if account.currencyCode != baseCurrency {
                            if let converted = engine.converter.convert(balance, from: account.currencyCode, to: baseCurrency) {
                                Text(verbatim: "≈ " + MoneyFormat.string(converted, code: baseCurrency))
                                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                            } else {
                                Text("Pending conversion").font(.footnote).foregroundStyle(DS.Colors.warning)
                            }
                        }
                    }
                    actions
                }
                .padding(.vertical, DS.Spacing.s)
            }

            Section("Account Info") {
                LabeledContent("Opening Balance", value: MoneyFormat.string(account.openingBalance, code: account.currencyCode))
                if account.openingDate > Date.distantPast.addingTimeInterval(86_400) {
                    LabeledContent("Balance As Of", value: account.openingDate.shortDateText)
                }
                if let reconciled = account.reconciledBalance, let at = account.reconciledAt {
                    LabeledContent("Reconciled Balance", value: MoneyFormat.string(reconciled, code: account.currencyCode))
                    LabeledContent("Reconciled On", value: at.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Included in Net Worth", value: account.includeInTotal ? String(localized: "Yes") : String(localized: "No"))
                if !account.note.isEmpty {
                    Text(account.note).foregroundStyle(.secondary)
                }
            }

            if list.isEmpty {
                Section {
                    Text("No transactions yet.").foregroundStyle(.secondary)
                }
            } else {
                ForEach(DayGroup.group(Array(list.prefix(visibleCount)))) { group in
                    Section(group.day.dayHeaderText) {
                        ForEach(group.entries) { entry in
                            NavigationLink(value: entry) {
                                TransactionRow(entry: entry, baseCurrency: baseCurrency, engine: engine, perspective: account.id)
                            }
                            .listRowBackground(entry.date < account.openingDate ? DS.Colors.fill : nil)
                        }
                    }
                }
                if list.count > visibleCount {
                    Section {
                        Button("Show More") { visibleCount += 200 }
                    }
                }
                if list.contains(where: { $0.date < account.openingDate }) {
                    Section {
                        Text("Shaded transactions are dated before the opening balance date; they appear in reports but are already included in the opening balance.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .pageBackground()
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor) { AccountEditorSheet(account: account) }
        .sheet(isPresented: $showReconcile) { ReconcileSheet(account: account, currentBalance: balance) }
    }

    private var actions: some View {
        HStack(spacing: DS.Spacing.s) {
            actionButton("Record", symbol: "plus") { router.addEntry(.expense, account: account) }
            if account.kind.isLiability {
                actionButton("Repay", symbol: "creditcard.and.123") { router.addEntry(.transfer, toAccount: account) }
            } else {
                actionButton("Transfer", symbol: "arrow.left.arrow.right") { router.addEntry(.transfer, account: account) }
            }
            actionButton("Reconcile", symbol: "checkmark.seal") { showReconcile = true }
        }
    }

    private func actionButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.body.weight(.semibold))
                Text(title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(DS.Colors.fill, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(.borderless)
        .tint(.primary)
    }
}

/// Enter the real balance; any difference is recorded as an audited adjustment.
struct ReconcileSheet: View {
    let account: Account
    let currentBalance: Decimal

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @State private var actualText = ""
    @State private var note = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    /// Liability accounts are entered as the positive amount owed.
    private var actual: Decimal? {
        guard let v = DecimalCodec.parseLenient(actualText) else { return nil }
        return account.kind.isLiability ? -v.magnitudeValue : v
    }

    private var difference: Decimal? { actual.map { $0 - currentBalance } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(account.kind.isLiability ? String(localized: "Calculated amount owed") : String(localized: "Calculated balance"),
                                   value: MoneyFormat.string(account.kind.isLiability ? -currentBalance : currentBalance, code: account.currencyCode, reveal: true))
                    HStack {
                        Text(account.kind.isLiability ? String(localized: "Actual amount owed") : String(localized: "Actual balance"))
                        Spacer()
                        TextField("0", text: $actualText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($focused)
                    }
                    if let difference {
                        LabeledContent("Difference", value: MoneyFormat.string(difference, code: account.currencyCode, showPlusSign: true, reveal: true))
                            .foregroundStyle(difference == 0 ? Color.secondary : DS.Colors.warning)
                    }
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("If the balances differ, Tally records a Balance Adjustment for the difference. It changes only this account's balance and never counts as income or spending.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(DS.Colors.danger) }
                }
            }
            .navigationTitle("Reconcile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { confirm() }
                        .fontWeight(.semibold)
                        .disabled(actual == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { focused = true }
    }

    private func confirm() {
        guard let actual else { return }
        do {
            let entry = try TransactionService(context: context).reconcile(account, actualBalance: actual, currentBalance: currentBalance, note: note)
            Haptics.success()
            toasts.show(ToastMessage(symbol: "checkmark.seal", text: entry == nil ? String(localized: "Balance confirmed") : String(localized: "Adjustment recorded"), style: .success))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
