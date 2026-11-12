import SwiftUI
import Charts

// MARK: - Hero

struct HeroBalanceCard: View {
    var period: Period
    var summary: PeriodSummary
    var previous: PeriodSummary
    var overall: BudgetStatus?
    var base: String
    var onShift: (Int) -> Void

    @GestureState private var dragX: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            HStack {
                Group {
                    if period.isCurrent { Text("Balance this month") } else { Text("Balance") }
                }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    shiftButton(-1, symbol: "chevron.left", label: "Previous month")
                    shiftButton(1, symbol: "chevron.right", label: "Next month")
                        .disabled(period.next.isFuture)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                AmountText(value: summary.net, code: base, font: DS.Typography.heroAmount, showPlusSign: summary.net > 0)
                if let delta = expenseDelta {
                    HStack(spacing: 4) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        if delta >= 0 {
                            Text("Spending \(MoneyFormat.percent(abs(delta))) more than this time last month")
                        } else {
                            Text("Spending \(MoneyFormat.percent(abs(delta))) less than this time last month")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                }
            }

            HStack(alignment: .top) {
                MetricView(title: "Income", value: summary.income, code: base, color: DS.Colors.income, symbol: "arrow.down.left")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(DS.Colors.separator.opacity(0.5)).frame(width: 0.5, height: 36)
                MetricView(title: "Expenses", value: summary.expense, code: base, symbol: "arrow.up.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, DS.Spacing.l)
            }

            if let overall {
                VStack(alignment: .leading, spacing: 8) {
                    CapsuleProgress(fraction: overall.fraction, tint: DS.Colors.budget(overall.level))
                    HStack {
                        if overall.remaining >= 0 {
                            Text("\(MoneyFormat.string(overall.remaining, code: base)) left of \(MoneyFormat.string(overall.limit, code: base))")
                        } else {
                            Text("\(MoneyFormat.string(-overall.remaining, code: base)) over budget")
                        }
                        Spacer()
                        if let daily = BudgetEvaluator.dailyAllowance(for: overall, period: period), daily > 0 {
                            Text("\(MoneyFormat.string(daily, code: base)) / day")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .card(padding: DS.Spacing.xl)
        .offset(x: dragX * 0.25)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .updating($dragX) { value, state, _ in
                    if abs(value.translation.width) > abs(value.translation.height) { state = value.translation.width }
                }
                .onEnded { value in
                    guard abs(value.translation.width) > 70, abs(value.translation.width) > abs(value.translation.height) else { return }
                    onShift(value.translation.width < 0 ? 1 : -1)
                }
        )
        .animation(DS.Motion.adaptive(DS.Motion.spring), value: dragX)
        .accessibilityAction(named: Text("Previous month")) { onShift(-1) }
        .accessibilityAction(named: Text("Next month")) { onShift(1) }
    }

    private var expenseDelta: Double? {
        guard previous.expense > 0, summary.expense > 0 else { return nil }
        return ((summary.expense - previous.expense) / previous.expense).doubleValue
    }

    private func shiftButton(_ delta: Int, symbol: String, label: LocalizedStringKey) -> some View {
        Button {
            onShift(delta)
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(DS.Colors.fill, in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Budget reminder

struct BudgetReminderCard: View {
    var status: BudgetStatus
    var base: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.m) {
                ZStack {
                    RingProgress(fraction: status.fraction, tint: DS.Colors.budget(status.level), lineWidth: 4)
                        .frame(width: 34, height: 34)
                    Image(systemName: status.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Colors.budget(status.level))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if status.level == .exceeded {
                            Text("Over budget: \(status.title)")
                        } else {
                            Text("Heads up: \(status.title)")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    Group {
                        if status.level == .exceeded {
                            Text("\(MoneyFormat.string(-status.remaining, code: base)) over this month")
                        } else {
                            Text("\(MoneyFormat.percent(status.fraction)) used · \(MoneyFormat.string(status.remaining, code: base)) left")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card(padding: 14, radius: DS.Radius.inner + 4)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Net worth

struct NetWorthCard: View {
    var accounts: [Account]
    var balances: [UUID: Decimal]
    var netWorth: NetWorth
    var base: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total assets")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    AmountText(value: netWorth.net, code: base, font: DS.Typography.cardAmount)
                }
                Spacer()
                NavigationLink {
                    AccountsListView()
                } label: {
                    HStack(spacing: 2) {
                        Text("Accounts")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                }
            }

            if netWorth.liabilities < 0 {
                HStack(spacing: DS.Spacing.l) {
                    Label {
                        Text(MoneyFormat.string(netWorth.assets, code: base))
                    } icon: {
                        Circle().fill(DS.Colors.income).frame(width: 6, height: 6)
                    }
                    Label {
                        Text(MoneyFormat.string(netWorth.liabilities, code: base))
                    } icon: {
                        Circle().fill(DS.Colors.danger).frame(width: 6, height: 6)
                    }
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if accounts.isEmpty {
                Text("Add an account to start tracking balances.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(accounts) { account in
                            NavigationLink(value: account) {
                                AccountTile(account: account, balance: balances[account.id] ?? account.openingBalance)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -DS.Spacing.xl)
            }

            if !netWorth.unconvertedCurrencies.isEmpty {
                Label("Missing exchange rate for \(netWorth.unconvertedCurrencies.sorted().joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(DS.Colors.warning)
            }
        }
        .card(padding: DS.Spacing.xl)
    }
}

struct AccountTile: View {
    var account: Account
    var balance: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SymbolBadge(symbol: account.symbolName, colorHex: account.colorHex, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(MoneyFormat.string(balance, code: account.currencyCode))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(balance < 0 ? DS.Colors.danger : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText(value: balance.doubleValue))
            }
        }
        .frame(width: 128, alignment: .leading)
        .padding(12)
        .background(DS.Colors.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Trend

struct SpendingTrendCard: View {
    var period: Period
    var current: [DayPoint]
    var previous: [DayPoint]
    var base: String

    @State private var selectedDay: Int?

    private struct Point: Identifiable {
        let id: String
        let day: Int
        let amount: Double
        let series: String
    }

    private var currentPoints: [Point] {
        current.map { Point(id: "c\($0.date.timeIntervalSince1970)", day: Calendar.current.component(.day, from: $0.date), amount: $0.amount.doubleValue, series: "current") }
    }

    private var previousPoints: [Point] {
        previous.map { Point(id: "p\($0.date.timeIntervalSince1970)", day: Calendar.current.component(.day, from: $0.date), amount: $0.amount.doubleValue, series: "previous") }
    }

    private var selectedCurrent: Point? {
        guard let selectedDay else { return nil }
        return currentPoints.last { $0.day <= selectedDay }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spending trend")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 12) {
                    legend(color: DS.Colors.accent, title: "This month", dashed: false)
                    legend(color: .secondary, title: "Last month", dashed: true)
                }
                .font(.caption2)
            }

            if let point = selectedCurrent {
                Text("Day \(point.day): \(MoneyFormat.string(Decimal(point.amount), code: base))")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .transition(.opacity)
            } else {
                Text(MoneyFormat.string(current.last?.amount ?? 0, code: base))
                    .font(DS.Typography.metric)
                    .monospacedDigit()
            }

            Chart {
                ForEach(previousPoints) { p in
                    LineMark(x: .value("Day", p.day), y: .value("Amount", p.amount), series: .value("Series", p.series))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .interpolationMethod(.monotone)
                }
                ForEach(currentPoints) { p in
                    AreaMark(x: .value("Day", p.day), y: .value("Amount", p.amount))
                        .foregroundStyle(
                            LinearGradient(colors: [DS.Colors.accent.opacity(0.22), DS.Colors.accent.opacity(0.0)], startPoint: .top, endPoint: .bottom)
                        )
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", p.day), y: .value("Amount", p.amount), series: .value("Series", p.series))
                        .foregroundStyle(DS.Colors.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let point = selectedCurrent {
                    RuleMark(x: .value("Day", point.day))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Day", point.day), y: .value("Amount", point.amount))
                        .foregroundStyle(DS.Colors.accent)
                        .symbolSize(70)
                }
            }
            .chartXScale(domain: 1...max(28, period.dayCount))
            .chartXAxis {
                AxisMarks(values: [1, 8, 15, 22, period.dayCount]) { value in
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(MoneyFormat.compact(v)) }
                    }
                }
            }
            .chartXSelection(value: $selectedDay)
            .frame(height: 150)
            .animation(DS.Motion.adaptive(DS.Motion.gentle), value: current)
            .accessibilityLabel(Text("Spending trend"))
        }
        .card(padding: DS.Spacing.xl)
        .onChange(of: selectedDay) { old, new in
            if new != nil && new != old { Haptics.selection() }
        }
    }

    private func legend(color: Color, title: LocalizedStringKey, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [2, 2] : []))
                .frame(width: 12, height: 2)
            Text(title).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Recent

struct RecentActivityCard: View {
    var entries: [LedgerEntry]
    var values: [UUID: Decimal]
    var base: String
    var onSeeAll: () -> Void
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack {
                Text("Recent")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !entries.isEmpty {
                    Button("See All", action: onSeeAll)
                        .font(.subheadline.weight(.medium))
                }
            }

            if entries.isEmpty {
                VStack(spacing: DS.Spacing.m) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No transactions this month")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Add Transaction", action: onAdd)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.l)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink(value: entry) {
                            TransactionRow(entry: entry, baseCurrency: base, baseValue: values[entry.id], showsDate: true)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if index < entries.count - 1 {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
            }
        }
        .card(padding: DS.Spacing.xl)
    }
}
