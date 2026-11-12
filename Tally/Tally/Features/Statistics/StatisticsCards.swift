import SwiftUI
import Charts

// MARK: - Summary

struct StatsSummaryCard: View {
    var kind: CategoryKind
    var period: Period
    var total: Decimal
    var previousTotal: Decimal
    var count: Int
    var base: String

    private var average: Decimal {
        switch period.unit {
        case .month:
            let days = max(1, period.elapsedDayCount)
            return (total / Decimal(days)).rounded(scale: 2)
        case .year:
            let months = period.months.filter { $0.start <= .now }.count
            return (total / Decimal(max(1, months))).rounded(scale: 2)
        }
    }

    private var change: Double? {
        guard previousTotal > 0 else { return nil }
        return ((total - previousTotal) / previousTotal).doubleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if kind == .expense { Text("Total spent") } else { Text("Total earned") }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                AmountText(value: total, code: base, font: DS.Typography.heroAmount, color: kind == .income ? DS.Colors.income : .primary)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Group {
                        if period.unit == .month { Text("Daily average") } else { Text("Monthly average") }
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                    AmountText(value: average, code: base, font: DS.Typography.metric)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text("vs. previous").font(.footnote).foregroundStyle(.secondary)
                    if let change {
                        HStack(spacing: 3) {
                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption.weight(.bold))
                            Text(MoneyFormat.percent(abs(change)))
                                .font(DS.Typography.metric)
                        }
                        .foregroundStyle(changeColor(change))
                    } else {
                        Text(verbatim: "—").font(DS.Typography.metric).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Entries").font(.footnote).foregroundStyle(.secondary)
                    Text(count.formatted())
                        .font(DS.Typography.metric)
                        .contentTransition(.numericText(value: Double(count)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card(padding: DS.Spacing.xl)
    }

    private func changeColor(_ change: Double) -> Color {
        if kind == .expense { return change > 0 ? DS.Colors.warning : DS.Colors.income }
        return change >= 0 ? DS.Colors.income : DS.Colors.warning
    }
}

// MARK: - Donut

struct CategoryDonutCard: View {
    var slices: [CategorySlice]
    var total: Decimal
    var base: String
    var kind: CategoryKind
    var period: Period

    @State private var selectedValue: Double?
    @State private var selectedID: String?

    private var selected: CategorySlice? {
        guard let selectedID else { return nil }
        return slices.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            Text("By category")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if slices.isEmpty {
                emptyChart
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Amount", slice.amount.doubleValue),
                        innerRadius: .ratio(0.64),
                        outerRadius: .ratio(selectedID == slice.id ? 1.0 : 0.93),
                        angularInset: 1.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(Color(hex: slice.colorHex))
                    .opacity(selectedID == nil || selectedID == slice.id ? 1 : 0.35)
                    .accessibilityLabel(Text(slice.name))
                    .accessibilityValue(Text(MoneyFormat.string(slice.amount, code: base)))
                }
                .chartAngleSelection(value: $selectedValue)
                .chartBackground { proxy in
                    GeometryReader { geo in
                        if let frame = proxy.plotFrame {
                            let rect = geo[frame]
                            VStack(spacing: 2) {
                                if let selected {
                                    Text(selected.name)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text(MoneyFormat.string(selected.amount, code: base))
                                        .font(.headline.monospacedDigit())
                                    Text(MoneyFormat.percent(selected.fraction, digits: 1))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Group {
                                        if kind == .expense { Text("Spent") } else { Text("Earned") }
                                    }
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    Text(MoneyFormat.string(total, code: base))
                                        .font(.headline.monospacedDigit())
                                        .minimumScaleFactor(0.6)
                                }
                            }
                            .lineLimit(1)
                            .frame(width: rect.width * 0.55)
                            .position(x: rect.midX, y: rect.midY)
                            .contentTransition(.opacity)
                        }
                    }
                }
                .frame(height: 230)
                .animation(DS.Motion.adaptive(DS.Motion.spring), value: selectedID)

                legend
            }
        }
        .card(padding: DS.Spacing.xl)
        .onChange(of: selectedValue) { _, value in
            guard let value else { return }
            var cumulative = 0.0
            for slice in slices {
                cumulative += slice.amount.doubleValue
                if value <= cumulative {
                    if selectedID != slice.id {
                        Haptics.selection()
                        selectedID = slice.id
                    } else {
                        selectedID = nil
                    }
                    return
                }
            }
        }
        .onChange(of: slices.map(\.id)) { _, _ in selectedID = nil }
    }

    private var legend: some View {
        FlowLayout(spacing: 10) {
            ForEach(slices.prefix(8)) { slice in
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: slice.colorHex)).frame(width: 7, height: 7)
                    Text(slice.name).font(.caption).foregroundStyle(.secondary)
                }
                .onTapGesture {
                    Haptics.selection()
                    withMotion(DS.Motion.snappy) { selectedID = selectedID == slice.id ? nil : slice.id }
                }
            }
        }
    }

    private var emptyChart: some View {
        VStack(spacing: DS.Spacing.s) {
            Image(systemName: "chart.pie")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No data for this period")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

// MARK: - Daily bars (month view)

struct DailyBarsCard: View {
    var points: [DayPoint]
    var kind: CategoryKind
    var base: String

    @State private var selectedDate: Date?

    private var selectedPoint: DayPoint? {
        guard let selectedDate else { return nil }
        return points.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var tint: Color { kind == .expense ? DS.Colors.accent : DS.Colors.income }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack {
                Text("Daily").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if let p = selectedPoint {
                    Text(verbatim: p.date.formatted(.dateTime.month(.abbreviated).day()) + " · " + MoneyFormat.string(p.amount, code: base))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .transition(.opacity)
                }
            }
            Chart(points) { p in
                BarMark(x: .value("Day", p.date, unit: .day), y: .value("Amount", p.amount.doubleValue))
                    .foregroundStyle(tint.opacity(selectedPoint == nil || selectedPoint?.date == p.date ? 1 : 0.35))
                    .cornerRadius(3)
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(MoneyFormat.compact(v)) } }
                }
            }
            .frame(height: 170)
        }
        .card(padding: DS.Spacing.xl)
        .onChange(of: selectedDate) { _, new in if new != nil { Haptics.selection() } }
    }
}

// MARK: - Year trend (income vs expense lines)

struct YearTrendCard: View {
    var points: [MonthPoint]
    var base: String

    @State private var selectedMonth: Date?

    private struct Line: Identifiable {
        var id: String { series + "\(month.timeIntervalSince1970)" }
        let month: Date
        let value: Double
        let series: String
    }

    private var lines: [Line] {
        points.flatMap { p in
            [Line(month: p.month, value: p.income.doubleValue, series: String(localized: "Income")),
             Line(month: p.month, value: p.expense.doubleValue, series: String(localized: "Expenses"))]
        }
    }

    private var selected: MonthPoint? {
        guard let selectedMonth else { return nil }
        return points.first { Calendar.current.isDate($0.month, equalTo: selectedMonth, toGranularity: .month) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack {
                Text("Income & expenses").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if let selected {
                    Text(verbatim: selected.month.shortMonthTitle + " · " + MoneyFormat.string(selected.net, code: base, showPlusSign: true))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                }
            }
            Chart {
                ForEach(lines) { line in
                    LineMark(x: .value("Month", line.month, unit: .month), y: .value("Amount", line.value))
                        .foregroundStyle(by: .value("Series", line.series))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    PointMark(x: .value("Month", line.month, unit: .month), y: .value("Amount", line.value))
                        .foregroundStyle(by: .value("Series", line.series))
                        .symbolSize(18)
                }
                if let selected {
                    RuleMark(x: .value("Month", selected.month, unit: .month))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                }
            }
            .chartForegroundStyleScale([
                String(localized: "Income"): DS.Colors.income,
                String(localized: "Expenses"): DS.Colors.accent,
            ])
            .chartXSelection(value: $selectedMonth)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
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
            .frame(height: 190)
        }
        .card(padding: DS.Spacing.xl)
        .onChange(of: selectedMonth) { _, new in if new != nil { Haptics.selection() } }
    }
}

// MARK: - Comparison

struct ComparisonCard: View {
    var points: [MonthPoint]
    var base: String
    var unit: Period.Unit

    private struct Bar: Identifiable {
        var id: String { series + label }
        let label: String
        let value: Double
        let series: String
    }

    private func label(_ date: Date) -> String {
        unit == .month ? date.shortMonthTitle : date.yearTitle
    }

    private var bars: [Bar] {
        points.flatMap { p in
            [Bar(label: label(p.month), value: p.income.doubleValue, series: String(localized: "Income")),
             Bar(label: label(p.month), value: p.expense.doubleValue, series: String(localized: "Expenses"))]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Group {
                if unit == .month { Text("Last 6 months") } else { Text("Year over year") }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)

            Chart(bars) { bar in
                BarMark(x: .value("Period", bar.label), y: .value("Amount", bar.value), width: .ratio(0.7))
                    .foregroundStyle(by: .value("Series", bar.series))
                    .position(by: .value("Series", bar.series))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale([
                String(localized: "Income"): DS.Colors.income,
                String(localized: "Expenses"): DS.Colors.accent,
            ])
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(MoneyFormat.compact(v)) } }
                }
            }
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 180)

            if let last = points.last {
                HStack {
                    Text("Net")
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

// MARK: - Ranking

struct CategoryRankingCard: View {
    var slices: [CategorySlice]
    var base: String
    var period: Period
    var kind: CategoryKind

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("Ranking").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            if slices.isEmpty {
                Text("Nothing recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DS.Spacing.s)
            }
            ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                NavigationLink(value: CategoryFocus(
                    categoryID: slice.categoryID,
                    name: slice.name,
                    kind: kind,
                    start: period.start,
                    end: period.end,
                    periodTitle: period.title
                )) {
                    HStack(spacing: DS.Spacing.m) {
                        SymbolBadge(symbol: slice.symbolName, colorHex: slice.colorHex, size: 34)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(slice.name).font(.subheadline.weight(.medium))
                                Text(MoneyFormat.percent(slice.fraction, digits: 1))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(MoneyFormat.string(slice.amount, code: base))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                            }
                            CapsuleProgress(fraction: relative(slice), tint: Color(hex: slice.colorHex), height: 5)
                        }
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < slices.count - 1 { Divider().padding(.leading, 46) }
            }
        }
        .card(padding: DS.Spacing.xl)
    }

    /// Bar length relative to the largest category.
    private func relative(_ slice: CategorySlice) -> Double {
        guard let top = slices.first?.amount, top > 0 else { return 0 }
        return (slice.amount / top).doubleValue
    }
}
