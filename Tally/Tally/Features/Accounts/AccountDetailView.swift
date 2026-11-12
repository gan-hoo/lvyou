import SwiftUI
import SwiftData

struct AccountDetailView: View {
    let account: Account

    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var rates: [ExchangeRate]
    @State private var showEditor = false

    var body: some View {
        if account.isDeleted || account.modelContext == nil {
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }

    private var content: some View {
        let math = LedgerMath(base: baseCurrency, rates: rates)
        let id = account.id
        let related = entries.filter { $0.account?.id == id || $0.toAccount?.id == id }
        let balance = math.balances(accounts: [account], entries: related)[id] ?? account.openingBalance
        let month = Period.month()
        let monthRelated = related.filter { month.contains($0.date) }
        let inflow = monthRelated.sum { e -> Decimal in
            switch e.kind {
            case .income: return e.account?.id == id ? e.amount : 0
            case .transfer: return e.toAccount?.id == id ? e.toAmount : 0
            case .expense: return 0
            }
        }
        let outflow = monthRelated.sum { e -> Decimal in
            (e.kind == .expense || e.kind == .transfer) && e.account?.id == id ? e.amount : 0
        }

        return List {
            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    HStack(spacing: DS.Spacing.m) {
                        SymbolBadge(symbol: account.symbolName, colorHex: account.colorHex, size: 44, style: .solid)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name).font(.headline)
                            Text(verbatim: account.kind.title + " · " + account.currencyCode)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Balance").font(.subheadline).foregroundStyle(.secondary)
                        AmountText(value: balance, code: account.currencyCode, font: DS.Typography.heroAmount,
                                   color: balance < 0 ? DS.Colors.danger : .primary)
                        if account.currencyCode != baseCurrency {
                            Text(verbatim: "≈ " + MoneyFormat.string(math.converter.convertOrSame(balance, from: account.currencyCode, to: baseCurrency), code: baseCurrency))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        MetricView(title: "In this month", value: inflow, code: account.currencyCode, color: DS.Colors.income, symbol: "arrow.down.left")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        MetricView(title: "Out this month", value: outflow, code: account.currencyCode, symbol: "arrow.up.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: DS.Spacing.m) {
                        Button {
                            router.addEntry(.expense, account: account)
                        } label: {
                            Label("Record", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            router.addEntry(.transfer, account: account)
                        } label: {
                            Label("Transfer", systemImage: "arrow.left.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
                .padding(.vertical, DS.Spacing.s)
            }

            if related.isEmpty {
                Section {
                    Text("No transactions yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(TransactionFilter.groupByDay(Array(related.prefix(300)), math: math)) { group in
                    Section(group.day.dayHeaderText) {
                        ForEach(group.entries) { entry in
                            NavigationLink(value: entry) {
                                TransactionRow(entry: entry, baseCurrency: baseCurrency, baseValue: math.value(entry))
                            }
                        }
                    }
                }
            }

            Section {
                LabeledContent("Opening balance", value: MoneyFormat.string(account.openingBalance, code: account.currencyCode))
                LabeledContent("Transactions", value: related.count.formatted())
                LabeledContent("Included in totals", value: account.includeInTotal ? String(localized: "Yes") : String(localized: "No"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor) {
            AccountEditorSheet(account: account)
        }
    }
}
