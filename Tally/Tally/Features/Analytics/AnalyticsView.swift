import SwiftUI
import SwiftData
import Charts

struct AnalyticsResult: Sendable, Equatable {
    var report = PeriodReport()
    var previous = PeriodReport()
    var expenseShares: [CategoryShare] = []
    var incomeShares: [CategoryShare] = []
    var daily: [DayPoint] = []
    /// Months for trend/comparison charts.
    var months: [MonthPoint] = []
}

/// How money was earned and spent in a period. Read-only: no account or budget editing here.
struct AnalyticsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LedgerCache.self) private var cache
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var unit: Period.Unit = .month
    @State private var period = Period.month()
    @State private var kind: CategoryKind = .expense
    @State private var result = AnalyticsResult()
    @State private var showCustom = false
    @State private var customPeriod: Period?

    private var taskKey: String { "\(cache.version)|\(baseCurrency)|\(period.start.timeIntervalSince1970)|\(period.end.timeIntervalSince1970)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.l) {
                    controls
                    OverviewCard(result: result, period: period, base: baseCurrency)
                    CategoryCard(
                        shares: kind == .expense ? result.expenseShares : result.incomeShares,
                        kind: $kind,
                        categories: categories,
                        base: baseCurrency
                    ) { share in
                        router.showTransactions(TransactionQuery(period: period, categoryID: share.categoryID,
                                                                 kinds: kind == .expense ? [.expense, .refund, .transfer] : [.income]))
                    }
                    if period.dayCount <= 62 {
                        DailyCard(points: result.daily, base: baseCurrency)
                    }
                    MonthlyCard(points: result.months, base: baseCurrency)
                    NetTrendCard(points: result.months, base: baseCurrency)
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.bottom, DS.Spacing.xxl)
                .animation(DS.Motion.adaptive(DS.Motion.spring), value: result)
            }
            .background(PageBackground())
            .navigationTitle("Analytics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AddMenuButton() }
            }
            .task(id: taskKey) { await recompute() }
            .sheet(isPresented: $showCustom, onDismiss: {
                // Cancelled without choosing a range: go back to the current unit.
                if customPeriod == nil && period.unit != .custom { unit = period.unit }
            }) {
                DateRangeSheet(period: $customPeriod)
            }
            .onChange(of: customPeriod) { _, new in
                if let new { withMotion { period = new } }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: DS.Spacing.m) {
            Picker("Period", selection: $unit) {
                ForEach(Period.Unit.allCases) { u in Text(u.title).tag(u) }
            }
            .pickerStyle(.segmented)
            .onChange(of: unit) { _, newUnit in
                if newUnit == .custom {
                    customPeriod = nil
                    showCustom = true
                } else {
                    let anchor = period.contains(.now) ? Date.now : period.start
                    withMotion { period = Period(unit: newUnit, containing: anchor) }
                }
            }

            HStack {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                }
                .accessibilityLabel(Text("Previous period"))
                Spacer()
                Button {
                    if unit == .custom { showCustom = true }
                } label: {
                    Text(period.title).font(.headline).foregroundStyle(.primary)
                }
                .disabled(unit != .custom)
                Spacer()
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                }
                .disabled(period.next.isFuture)
                .accessibilityLabel(Text("Next period"))
            }
        }
        .padding(.top, DS.Spacing.s)
    }

    private func shift(_ delta: Int) {
        let target = period.shifted(by: delta)
        guard !target.isFuture else { return }
        Haptics.selection()
        withMotion { period = target }
    }

    private func recompute() async {
        let p = period
        let base = baseCurrency
        let key = "analytics|\(base)|\(p.start.timeIntervalSince1970)|\(p.end.timeIntervalSince1970)"
        let r = await cache.compute(key) { snapshot, converter in
            let engine = FinanceEngine(base: base, converter: converter)
            let entries = snapshot.entries
            var out = AnalyticsResult()
            out.report = engine.report(entries, in: p)
            let previous = p.previous
            out.previous = engine.report(entries, in: previous, endingBefore: p.comparableEnd(in: previous))
            out.expenseShares = engine.categoryShares(entries, in: p, kind: .expense)
            out.incomeShares = engine.categoryShares(entries, in: p, kind: .income)
            if p.dayCount <= 62 { out.daily = engine.dailyExpense(entries, in: p) }
            // Year view: the year's months; otherwise the last six months up to this period.
            let months: [Period]
            if p.unit == .year {
                months = p.months
            } else {
                let last = Period.month(p.end.addingTimeInterval(-1))
                months = (0..<6).reversed().map { last.shifted(by: -$0) }
            }
            out.months = engine.monthly(entries, months: months)
            return out
        }
        result = r
    }
}

// MARK: - Overview

private struct OverviewCard: View {
    let result: AnalyticsResult
    let period: Period
    let base: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            HStack(alignment: .top) {
                metric("Income", result.report.income, result.previous.income, color: DS.Colors.income, higherIsGood: true)
                metric("Expenses", result.report.expense, result.previous.expense, color: .primary, higherIsGood: false)
                metric("Net", result.report.net, result.previous.net, color: result.report.net < 0 ? DS.Colors.danger : .primary, higherIsGood: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if result.report.refunds > 0 {
                    Text("Refunds of \(MoneyFormat.string(result.report.refunds, code: base)) are subtracted from expenses.")
                }
                if result.report.fees > 0 {
                    Text("Expenses include transfer fees of \(MoneyFormat.string(result.report.fees, code: base)).")
                }
                Text("Net = income − expenses for this period (cash flow). Transfers, card repayments and balance adjustments are excluded; this is not the change in net worth.")
                if result.report.pendingCount > 0 {
                    Text("\(result.report.pendingCount) transactions are waiting for an exchange rate and are not included.")
                        .foregroundStyle(DS.Colors.warning)
                }
                Text("Amounts in \(base) use each transaction's saved rate, or the historical rate on its date.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .card(padding: DS.Spacing.xl)
    }

    private func metric(_ title: LocalizedStringKey, _ value: Decimal, _ previous: Decimal, color: Color, higherIsGood: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            AmountText(value: value, code: base, font: DS.Typography.metric, color: color)
            if previous != 0 {
                let change = ((value - previous) / previous.magnitudeValue).doubleValue
                HStack(spacing: 2) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(MoneyFormat.percent(abs(change)))
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle((change >= 0) == higherIsGood ? DS.Colors.income : DS.Colors.warning)
                .accessibilityLabel(Text("vs. previous"))
            } else {
                Text(verbatim: "—").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Categories

private struct CategoryCard: View {
    let shares: [CategoryShare]
    @Binding var kind: CategoryKind
    let categories: [LedgerCategory]
    let base: String
    var onSelect: (CategoryShare) -> Void

    @State private var selectedValue: Double?
    @State private var selectedID: String?

    private func info(_ share: CategoryShare) -> (name: String, symbol: String, color: String) {
        if let c = categories.first(where: { $0.id == share.categoryID }) { return (c.name, c.symbolName, c.colorHex) }
        return (String(localized: "Uncategorized"), "questionmark", "8E8E93")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            HStack {
                Text("By Category").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Picker("Type", selection: $kind) {
                    ForEach(CategoryKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            if shares.isEmpty {
                VStack(spacing: DS.Spacing.s) {
                    Image(systemName: "chart.pie").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No data for this period").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                Chart(shares) { share in
                    SectorMark(
                        angle: .value("Amount", share.amount.doubleValue),
                        innerRadius: .ratio(0.64),
                        outerRadius: .ratio(selectedID == share.id ? 1.0 : 0.93),
                        angularInset: 1.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(Color(hex: info(share).color))
                    .opacity(selectedID == nil || selectedID == share.id ? 1 : 0.35)
                    .accessibilityLabel(Text(info(share).name))
                    .accessibilityValue(Text(MoneyFormat.string(share.amount, code: base)))
                }
                .chartAngleSelection(value: $selectedValue)
                .chartBackground { proxy in
                    GeometryReader { geo in
                        if let frame = proxy.plotFrame {
                            let rect = geo[frame]
                            let total = shares.sum { $0.amount }
                            let selected = shares.first { $0.id == selectedID }
                            VStack(spacing: 2) {
                                Text(selected.map { info($0).name } ?? (kind == .expense ? String(localized: "Spent") : String(localized: "Earned")))
                                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                                Text(MoneyFormat.string(selected?.amount ?? total, code: base))
                                    .font(.headline.monospacedDigit())
                                    .minimumScaleFactor(0.6)
                                if let selected {
                                    Text(MoneyFormat.percent(selected.fraction, digits: 1)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .lineLimit(1)
                            .frame(width: rect.width * 0.55)
                            .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
                .frame(height: 220)
                .animation(DS.Motion.adaptive(DS.Motion.spring), value: selectedID)

                VStack(spacing: 0) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        let i = info(share)
                        Button { onSelect(share) } label: {
                            HStack(spacing: DS.Spacing.m) {
                                SymbolBadge(symbol: i.symbol, colorHex: i.color, size: 32)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(i.name).font(.subheadline.weight(.medium))
                                        Text(MoneyFormat.percent(share.fraction, digits: 1)).font(.caption).foregroundStyle(.secondary)
                                        Spacer()
                                        Text(MoneyFormat.string(share.amount, code: base)).font(.subheadline.weight(.semibold).monospacedDigit())
                                    }
                                    CapsuleProgress(fraction: share.fraction / (shares.first?.fraction ?? 1), tint: Color(hex: i.color), height: 4)
                                }
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < shares.count - 1 { Divider().padding(.leading, 44) }
                    }
                }
            }
        }
        .card(padding: DS.Spacing.xl)
        .onChange(of: selectedValue) { _, value in
            guard let value else { return }
            var cumulative = 0.0
            for share in shares {
                cumulative += share.amount.doubleValue
                if value <= cumulative {
                    Haptics.selection()
                    selectedID = selectedID == share.id ? nil : share.id
                    return
                }
            }
        }
        .onChange(of: shares.map(\.id)) { _, _ in selectedID = nil }
    }
}

// MARK: - Trends

private struct DailyCard: View {
    let points: [DayPoint]
    let base: String
    @State private var selectedDate: Date?

    private var selected: DayPoint? {
        guard let selectedDate else { return nil }
        return points.first { Calendar.ledger.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack {
                Text("Daily Spending").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if let p = selected {
                    Text(verbatim: p.date.formatted(.dateTime.month(.abbreviated).day()) + " · " + MoneyFormat.string(p.amount, code: base))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                }
            }
            Chart(points) { p in
                BarMark(x: .value("Day", p.date, unit: .day), y: .value("Amount", max(0, p.amount.doubleValue)))
                    .foregroundStyle(DS.Colors.accent.opacity(selected == nil || selected?.date == p.date ? 1 : 0.35))
                    .cornerRadius(3)
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(MoneyFormat.compact(v)) } }
                }
            }
            .frame(height: 160)
        }
        .card(padding: DS.Spacing.xl)
        .onChange(of: selectedDate) { _, new in if new != nil { Haptics.selection() } }
    }
}

private struct MonthlyCard: View {
    let points: [MonthPoint]
    let base: String

    private struct Bar: Identifiable {
        var id: String { series + "\(month.timeIntervalSince1970)" }
        let month: Date
        let value: Double
        let series: String
    }

    @State private var selectedMonth: Date?

    private var bars: [Bar] {
        points.flatMap { p in
            [Bar(month: p.month, value: p.income.doubleValue, series: String(localized: "Income")),
             Bar(month: p.month, value: max(0, p.expense.doubleValue), series: String(localized: "Expenses"))]
        }
    }

    private var selected: MonthPoint? {
        guard let selectedMonth else { return nil }
        return points.first { Calendar.ledger.isDate($0.month, equalTo: selectedMonth, toGranularity: .month) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack {
                Text("Monthly Income & Expenses").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if let s = selected {
                    Text(verbatim: s.month.shortMonthTitle + " · +" + MoneyFormat.string(s.income, code: base) + " / −" + MoneyFormat.string(s.expense, code: base))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Chart(bars) { bar in
                BarMark(x: .value("Month", bar.month, unit: .month), y: .value("Amount", bar.value), width: .ratio(0.7))
                    .foregroundStyle(by: .value("Series", bar.series))
                    .position(by: .value("Series", bar.series))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale([
                String(localized: "Income"): DS.Colors.income,
                String(localized: "Expenses"): DS.Colors.accent,
            ])
            .chartXSelection(value: $selectedMonth)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(MoneyFormat.compact(v)) } }
                }
            }
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 180)
        }
        .card(padding: DS.Spacing.xl)
        .onChange(of: selectedMonth) { _, new in if new != nil { Haptics.selection() } }
    }
}

private struct NetTrendCard: View {
    let points: [MonthPoint]
    let base: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("Monthly Net").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Chart(points) { p in
                BarMark(x: .value("Month", p.month, unit: .month), y: .value("Net", p.net.doubleValue))
                    .foregroundStyle(p.net >= 0 ? DS.Colors.income : DS.Colors.danger)
                    .cornerRadius(3)
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Color.secondary.opacity(0.3))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow)) }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(MoneyFormat.compact(v)) } }
                }
            }
            .frame(height: 140)
            if let last = points.last {
                HStack {
                    Text(last.month.monthTitle)
                    Spacer()
                    Text(MoneyFormat.string(last.net, code: base, showPlusSign: true))
                        .foregroundStyle(last.net >= 0 ? DS.Colors.income : DS.Colors.danger)
                        .monospacedDigit()
                }
                .font(.footnote.weight(.medium))
            }
        }
        .card(padding: DS.Spacing.xl)
    }
}
