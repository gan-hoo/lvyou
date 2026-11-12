import SwiftUI
import SwiftData

/// Drill-down: every entry of one category within a period.
struct CategoryEntriesView: View {
    let focus: CategoryFocus

    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @Query private var entries: [LedgerEntry]
    @Query private var rates: [ExchangeRate]

    init(focus: CategoryFocus) {
        self.focus = focus
        let start = focus.start, end = focus.end
        _entries = Query(filter: #Predicate<LedgerEntry> { $0.date >= start && $0.date < end }, sort: \.date, order: .reverse)
    }

    private var matching: [LedgerEntry] {
        entries.filter { $0.kind == focus.kind.transactionKind && $0.category?.id == focus.categoryID }
    }

    var body: some View {
        let math = LedgerMath(base: baseCurrency, rates: rates)
        let list = matching
        let total = list.sum { math.value($0) }

        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(focus.periodTitle).font(.subheadline).foregroundStyle(.secondary)
                        AmountText(value: total, code: baseCurrency, font: DS.Typography.cardAmount)
                    }
                    Spacer()
                    Text("\(list.count) items").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            ForEach(TransactionFilter.groupByDay(list, math: math)) { group in
                Section(group.day.dayHeaderText) {
                    ForEach(group.entries) { entry in
                        NavigationLink(value: entry) {
                            TransactionRow(entry: entry, baseCurrency: baseCurrency, baseValue: math.value(entry))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(focus.name)
        .overlay {
            if list.isEmpty {
                ContentUnavailableView("No Transactions", systemImage: "tray", description: Text("Nothing in this category for the selected period."))
            }
        }
    }
}
