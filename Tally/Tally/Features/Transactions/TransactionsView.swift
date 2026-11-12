import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase

    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var rates: [ExchangeRate]

    @State private var filter = TransactionFilter()
    @State private var searchText = ""
    @State private var showFilter = false
    @State private var pendingDelete: LedgerEntry?

    var body: some View {
        let math = LedgerMath(base: baseCurrency, rates: rates)
        let results = filter.apply(to: entries, search: searchText, math: math)
        let summary = math.summary(results)

        NavigationStack {
            List {
                if !results.isEmpty {
                    Section {
                        ResultsSummary(count: results.count, summary: summary, base: baseCurrency)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }

                if filter.sort.groupsByDay {
                    ForEach(TransactionFilter.groupByDay(results, math: math)) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                row(entry, math: math)
                            }
                        } header: {
                            DayHeader(group: group, base: baseCurrency)
                        }
                    }
                } else {
                    Section(filter.sort.title) {
                        ForEach(results) { entry in
                            row(entry, math: math, showsDate: true)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(DS.Colors.background)
            .animation(DS.Motion.adaptive(DS.Motion.spring), value: results.map(\.id))
            .searchable(text: $searchText, prompt: Text("Notes, categories, tags, amounts"))
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $filter.sort) {
                            ForEach(TransactionFilter.Sort.allCases) { sort in
                                Label(sort.title, systemImage: sort.symbol).tag(sort)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(Text("Sort"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilter = true
                    } label: {
                        Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(Text("Filter"))
                    .accessibilityValue(filter.isActive ? Text("\(filter.activeCount) active") : Text("Off"))
                }
            }
            .overlay {
                if results.isEmpty {
                    emptyState
                }
            }
            .overlay(alignment: .bottomTrailing) {
                FloatingAddButton { router.addEntry() }
                    .padding(.trailing, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.l)
            }
            .navigationDestination(for: LedgerEntry.self) { TransactionDetailView(entry: $0) }
            .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
            .sheet(isPresented: $showFilter) {
                TransactionFilterSheet(filter: $filter)
            }
            .confirmationDialog(
                "Delete this transaction?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { entry in
                Button("Delete", role: .destructive) {
                    withMotion { LedgerStore(context: context).delete(entry) }
                    Haptics.success()
                    pendingDelete = nil
                }
            } message: { _ in
                Text("This can't be undone.")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if filter.isActive {
            ContentUnavailableView {
                Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No transactions match the current filters.")
            } actions: {
                Button("Clear Filters") { withMotion { filter.reset() } }
            }
        } else {
            ContentUnavailableView {
                Label("No Transactions Yet", systemImage: "tray")
            } description: {
                Text("Tap + to record your first expense or income.")
            } actions: {
                Button("Add Transaction") { router.addEntry() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
    }

    private func row(_ entry: LedgerEntry, math: LedgerMath, showsDate: Bool = false) -> some View {
        NavigationLink(value: entry) {
            TransactionRow(entry: entry, baseCurrency: baseCurrency, baseValue: math.value(entry), showsDate: showsDate)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = entry
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                router.edit(entry)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(DS.Colors.accent)
        }
        .swipeActions(edge: .leading) {
            Button {
                duplicate(entry)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(DS.Colors.income)
        }
        .contextMenu {
            Button { router.edit(entry) } label: { Label("Edit", systemImage: "pencil") }
            Button { duplicate(entry) } label: { Label("Duplicate as Today", systemImage: "plus.square.on.square") }
            Divider()
            Button(role: .destructive) { pendingDelete = entry } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func duplicate(_ entry: LedgerEntry) {
        if LedgerStore(context: context).duplicate(entry) != nil {
            Haptics.success()
            toasts.show(ToastMessage(symbol: "plus.square.on.square", text: String(localized: "Duplicated to today"), style: .success))
        }
    }
}

private struct DayHeader: View {
    let group: DayGroup
    let base: String

    var body: some View {
        HStack {
            Text(group.day.dayHeaderText)
            Spacer()
            HStack(spacing: 10) {
                if group.income > 0 {
                    Text(MoneyFormat.string(group.income, code: base, showPlusSign: true))
                        .foregroundStyle(DS.Colors.income)
                }
                if group.expense > 0 {
                    Text(MoneyFormat.string(-group.expense, code: base))
                }
            }
            .monospacedDigit()
        }
        .font(.footnote.weight(.medium))
        .textCase(nil)
    }
}

private struct ResultsSummary: View {
    let count: Int
    let summary: PeriodSummary
    let base: String

    var body: some View {
        HStack(spacing: 0) {
            item(title: "Income", value: summary.income, color: DS.Colors.income)
            item(title: "Expenses", value: summary.expense, color: .primary)
            item(title: "Net", value: summary.net, color: .primary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(DS.Colors.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner + 2, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Text("\(count) items")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    private func item(title: LocalizedStringKey, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            AmountText(value: value, code: base, font: .subheadline.weight(.semibold), color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 8)
    }
}
