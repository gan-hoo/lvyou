import SwiftUI
import SwiftData
import Charts

struct StatisticsSnapshot {
    var summary = PeriodSummary()
    var previousSummary = PeriodSummary()
    var slices: [CategorySlice] = []
    var daily: [DayPoint] = []
    var monthly: [MonthPoint] = []
    var comparison: [MonthPoint] = []
}

struct StatisticsView: View {
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var rates: [ExchangeRate]

    @State private var unit: Period.Unit = .month
    @State private var period = Period.month()
    @State private var kind: CategoryKind = .expense

    var body: some View {
        let math = LedgerMath(base: baseCurrency, rates: rates)
        let snapshot = makeSnapshot(math: math)
        let total = kind == .expense ? snapshot.summary.expense : snapshot.summary.income
        let previousTotal = kind == .expense ? snapshot.previousSummary.expense : snapshot.previousSummary.income

        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.l) {
                    controls

                    StatsSummaryCard(
                        kind: kind,
                        period: period,
                        total: total,
                        previousTotal: previousTotal,
                        count: snapshot.slices.reduce(0) { $0 + $1.count },
                        base: baseCurrency
                    )

                    CategoryDonutCard(slices: snapshot.slices, total: total, base: baseCurrency, kind: kind, period: period)

                    if unit == .month {
                        DailyBarsCard(points: snapshot.daily, kind: kind, base: baseCurrency)
                    } else {
                        YearTrendCard(points: snapshot.monthly, base: baseCurrency)
                    }

                    ComparisonCard(points: snapshot.comparison, base: baseCurrency, unit: unit)

                    CategoryRankingCard(slices: snapshot.slices, base: baseCurrency, period: period, kind: kind)
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.bottom, DS.Spacing.xxl)
                .animation(DS.Motion.adaptive(DS.Motion.spring), value: period)
                .animation(DS.Motion.adaptive(DS.Motion.spring), value: kind)
            }
            .background(DS.Colors.background)
            .navigationTitle("Statistics")
            .navigationDestination(for: CategoryFocus.self) { focus in
                CategoryEntriesView(focus: focus)
            }
            .navigationDestination(for: LedgerEntry.self) { TransactionDetailView(entry: $0) }
            .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
        }
    }

    private var controls: some View {
        VStack(spacing: DS.Spacing.m) {
            Picker("Period", selection: $unit) {
                ForEach(Period.Unit.allCases) { u in Text(u.title).tag(u) }
            }
            .pickerStyle(.segmented)
            .onChange(of: unit) { _, newUnit in
                let anchor = period.contains(.now) ? Date.now : period.start
                withMotion { period = Period(unit: newUnit, containing: anchor) }
            }

            HStack {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                }
                .accessibilityLabel(Text("Previous period"))
                Spacer()
                Text(period.title)
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer()
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                }
                .disabled(period.next.isFuture)
                .accessibilityLabel(Text("Next period"))
            }

            Picker("Type", selection: $kind) {
                ForEach(CategoryKind.allCases) { k in Text(k.title).tag(k) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.top, DS.Spacing.s)
    }

    private func shift(_ delta: Int) {
        let target = period.shifted(by: delta)
        guard !target.isFuture else { return }
        Haptics.selection()
        withMotion { period = target }
    }

    private func makeSnapshot(math: LedgerMath) -> StatisticsSnapshot {
        var s = StatisticsSnapshot()
        let previous = period.previous
        var current: [LedgerEntry] = []
        var prior: [LedgerEntry] = []
        for e in entries {
            if period.contains(e.date) { current.append(e) }
            else if previous.contains(e.date) { prior.append(e) }
        }
        s.summary = math.summary(current)
        s.previousSummary = math.summary(prior)
        s.slices = math.categoryBreakdown(current, kind: kind.transactionKind)
        if unit == .month {
            s.daily = math.dailySeries(current, period: period, kind: kind.transactionKind)
            let months = (0..<6).reversed().map { period.shifted(by: -$0) }
            s.comparison = math.monthlySeries(entries.filter { $0.date >= months[0].start && $0.date < period.end }, months: months)
        } else {
            s.monthly = math.monthlySeries(current, months: period.months)
            let years = (0..<4).reversed().map { period.shifted(by: -$0) }
            s.comparison = years.map { y in
                let sum = math.summary(entries.filter { y.contains($0.date) })
                return MonthPoint(month: y.start, income: sum.income, expense: sum.expense)
            }
        }
        return s
    }
}

/// Navigation value for drilling into one category within a period.
struct CategoryFocus: Hashable {
    let categoryID: UUID?
    let name: String
    let kind: CategoryKind
    let start: Date
    let end: Date
    let periodTitle: String
}
