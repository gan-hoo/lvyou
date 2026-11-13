import SwiftUI
import SwiftData

/// The record of what happened: every entry, by period, searchable and filterable.
struct TransactionsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LedgerCache.self) private var cache
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase

    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]

    @State private var period: Period? = .month()
    @State private var filter = TransactionFilter()
    @State private var searchText = ""
    @State private var showFilter = false
    @State private var showCustomRange = false
    @State private var pendingDelete: LedgerEntry?
    /// Day picked in the calendar; nil shows the whole period.
    @State private var selectedDay: Date?
    @AppStorage("transactions.showCalendar") private var showCalendar = true

    /// The calendar is shown for calendar months.
    private var calendarVisible: Bool { showCalendar && period?.unit == .month }

    private func onSelectedDay<T>(_ items: [T], date: (T) -> Date) -> [T] {
        guard let day = selectedDay else { return items }
        return items.filter { Calendar.ledger.isDate(date($0), inSameDayAs: day) }
    }

    var body: some View {
        let engine = cache.engine(base: baseCurrency)
        let results = filter.apply(to: entries, period: period, search: searchText, engine: engine)
        let report = engine.report(results.map(EntryValue.init))
        let groups = DayGroup.group(results, engine: engine)
        let dayGroups = onSelectedDay(groups) { $0.day }
        let dayResults = onSelectedDay(results) { $0.date }

        NavigationStack {
            List {
                Section {
                    PeriodSwitcher(period: $period, showCustomRange: $showCustomRange)
                    if !results.isEmpty {
                        ResultsSummary(count: results.count, report: report, base: baseCurrency)
                    }
                    if calendarVisible, let month = period {
                        MonthCalendar(month: month, groups: groups, base: baseCurrency, selected: $selectedDay)
                            .padding(.top, 4)
                    }
                    if let day = selectedDay {
                        SelectedDayBar(day: day) { withMotion(DS.Motion.snappy) { selectedDay = nil } }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))

                if let day = selectedDay, dayResults.isEmpty {
                    Section {
                        VStack(spacing: DS.Spacing.s) {
                            Text("No transactions on this day.").font(.subheadline).foregroundStyle(.secondary)
                            Button("Add on This Day") {
                                router.entryRequest = EntryRequest(date: day.combining(timeOf: .now))
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.m)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if calendarVisible && results.isEmpty {
                    Section { emptyState }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if filter.sort.groupsByDay {
                    ForEach(dayGroups) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                row(entry, engine: engine)
                            }
                        } header: {
                            DayHeader(group: group, base: baseCurrency)
                        }
                    }
                } else {
                    Section(filter.sort.title) {
                        ForEach(dayResults) { entry in
                            row(entry, engine: engine, showsDate: true)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .pageBackground()
            .animation(DS.Motion.adaptive(DS.Motion.spring), value: results.count)
            .searchable(text: $searchText, prompt: Text("Notes, payees, categories, tags, amounts"))
            .tabRootTitle("Transactions")
            .toolbar { toolbarContent }
            .overlay {
                if results.isEmpty && !calendarVisible { emptyState }
            }
            .navigationDestination(for: LedgerEntry.self) { TransactionDetailView(entry: $0) }
            .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
            .sheet(isPresented: $showFilter) { TransactionFilterSheet(filter: $filter) }
            .sheet(isPresented: $showCustomRange) { DateRangeSheet(period: $period) }
            .confirmationDialog(
                "Delete this transaction?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { entry in
                Button("Delete", role: .destructive) { delete(entry) }
            } message: { _ in
                Text("This can't be undone. The deletion is kept in the change log.")
            }
            .onAppear(perform: applyPendingQuery)
            .onChange(of: router.pendingQuery) { _, _ in applyPendingQuery() }
            .onChange(of: period) { _, _ in selectedDay = nil }
        }
    }

    private func applyPendingQuery() {
        guard let q = router.pendingQuery else { return }
        router.pendingQuery = nil
        selectedDay = nil
        withMotion {
            period = q.period
            filter.reset()
            if let c = q.categoryID { filter.categoryIDs = [c] }
            if let a = q.accountID { filter.accountIDs = [a] }
            filter.kinds = q.kinds
            searchText = ""
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Sort", selection: $filter.sort) {
                    ForEach(TransactionFilter.Sort.allCases) { sort in
                        Label(sort.title, systemImage: sort.symbol).tag(sort)
                    }
                }
                Divider()
                NavigationLink {
                    RecurringListView()
                } label: {
                    Label("Recurring Plans", systemImage: "repeat")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(Text("More"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.selection()
                withMotion(DS.Motion.snappy) {
                    showCalendar.toggle()
                    if showCalendar, period?.unit != .month {
                        period = .month(period?.start ?? .now)
                    }
                    if !showCalendar { selectedDay = nil }
                }
            } label: {
                Image(systemName: calendarVisible ? "calendar.circle.fill" : "calendar.circle")
            }
            .accessibilityLabel(calendarVisible ? Text("Hide Calendar") : Text("Show Calendar"))
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
        ToolbarItem(placement: .topBarTrailing) {
            AddMenuButton()
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
                Label("No Transactions", systemImage: "tray")
            } description: {
                Text("Nothing recorded in this period. Tap + to record an expense or income.")
            } actions: {
                Button("Add Transaction") { router.addEntry() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
    }

    private func row(_ entry: LedgerEntry, engine: FinanceEngine, showsDate: Bool = false) -> some View {
        NavigationLink(value: entry) {
            TransactionRow(entry: entry, baseCurrency: baseCurrency, engine: engine, showsDate: showsDate)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { pendingDelete = entry } label: { Label("Delete", systemImage: "trash") }
            if entry.kind != .adjustment {
                Button { router.edit(entry) } label: { Label("Edit", systemImage: "pencil") }
                    .tint(DS.Colors.accent)
            }
        }
        .swipeActions(edge: .leading) {
            if entry.kind != .adjustment {
                Button { duplicate(entry) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .tint(DS.Colors.income)
            }
        }
        .contextMenu {
            if entry.kind != .adjustment {
                Button { router.edit(entry) } label: { Label("Edit", systemImage: "pencil") }
                Button { duplicate(entry) } label: { Label("Duplicate as Today", systemImage: "plus.square.on.square") }
            }
            if entry.kind == .expense {
                Button { router.refund(entry) } label: { Label("Record Refund", systemImage: "arrow.uturn.backward") }
            }
            Divider()
            Button(role: .destructive) { pendingDelete = entry } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func duplicate(_ entry: LedgerEntry) {
        do {
            try TransactionService(context: context).duplicate(entry)
            Haptics.success()
            toasts.show(ToastMessage(symbol: "plus.square.on.square", text: String(localized: "Duplicated to today"), style: .success))
        } catch {
            toasts.show(ToastMessage(symbol: "exclamationmark.triangle", text: error.localizedDescription, style: .warning))
        }
    }

    private func delete(_ entry: LedgerEntry) {
        do {
            try withMotion { try TransactionService(context: context).delete(entry) }
            Haptics.success()
        } catch {
            toasts.show(ToastMessage(symbol: "exclamationmark.triangle", text: error.localizedDescription, style: .warning))
        }
        pendingDelete = nil
    }
}

// MARK: - Period switcher

struct PeriodSwitcher: View {
    @Binding var period: Period?
    @Binding var showCustomRange: Bool

    var body: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 36, height: 36)
            }
            .disabled(period == nil)
            .accessibilityLabel(Text("Previous period"))
            Spacer()
            Menu {
                Button("This Week") { set(.week()) }
                Button("This Month") { set(.month()) }
                Button("This Year") { set(.year()) }
                Button("Custom Range…") { showCustomRange = true }
                Divider()
                Button("All Time") { set(nil) }
            } label: {
                HStack(spacing: 4) {
                    Text(period?.title ?? String(localized: "All Time"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 36, height: 36)
            }
            .disabled(period == nil || period?.next.isFuture == true)
            .accessibilityLabel(Text("Next period"))
        }
        .buttonStyle(.borderless)
    }

    private func set(_ p: Period?) {
        Haptics.selection()
        withMotion { period = p }
    }

    private func shift(_ delta: Int) {
        guard let p = period else { return }
        set(p.shifted(by: delta))
    }
}

struct DateRangeSheet: View {
    @Binding var period: Period?
    @Environment(\.dismiss) private var dismiss
    @State private var start = Calendar.ledger.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var end = Date.now

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        withMotion { period = Period(customFrom: start, through: end) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            if let period, period.unit == .custom {
                start = period.start
                end = period.end.addingTimeInterval(-1)
            }
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
                if group.expense != 0 {
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
    let report: PeriodReport
    let base: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                item(title: "Income", value: report.income, color: DS.Colors.income)
                item(title: "Expenses", value: report.expense, color: .primary)
                item(title: "Net", value: report.net, color: .primary)
            }
            HStack {
                Text("\(count) items")
                if report.pendingCount > 0 {
                    Text("· \(report.pendingCount) pending conversion").foregroundStyle(DS.Colors.warning)
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .card(padding: 0, radius: DS.Radius.inner + 2)
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
