import SwiftUI
import SwiftData

/// Everything the dashboard renders, computed once per update.
struct DashboardSnapshot {
    var summary = PeriodSummary()
    var previousSummary = PeriodSummary()
    var balances: [UUID: Decimal] = [:]
    var netWorth = NetWorth()
    var thisMonthSeries: [DayPoint] = []
    var lastMonthSeries: [DayPoint] = []
    var recent: [LedgerEntry] = []
    var budget = BudgetOverview()
    var values: [UUID: Decimal] = [:]
}

struct DashboardView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase

    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var rates: [ExchangeRate]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]

    @State private var period = Period.month()
    @State private var confirmClearDemo = false

    private var hasDemoData: Bool { accounts.contains { $0.isDemo } }

    var body: some View {
        let math = LedgerMath(base: baseCurrency, rates: rates)
        let snapshot = makeSnapshot(math: math)

        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.l) {
                    if hasDemoData {
                        DemoBanner { confirmClearDemo = true }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    HeroBalanceCard(
                        period: period,
                        summary: snapshot.summary,
                        previous: snapshot.previousSummary,
                        overall: snapshot.budget.overall,
                        base: baseCurrency,
                        onShift: shift
                    )

                    if let urgent = snapshot.budget.mostUrgent, period.isCurrent {
                        BudgetReminderCard(status: urgent, base: baseCurrency) { router.show(.budget) }
                            .transition(.opacity)
                    }

                    NetWorthCard(
                        accounts: accounts.filter { !$0.isArchived },
                        balances: snapshot.balances,
                        netWorth: snapshot.netWorth,
                        base: baseCurrency
                    )

                    SpendingTrendCard(
                        period: period,
                        current: snapshot.thisMonthSeries,
                        previous: snapshot.lastMonthSeries,
                        base: baseCurrency
                    )

                    RecentActivityCard(
                        entries: snapshot.recent,
                        values: snapshot.values,
                        base: baseCurrency,
                        onSeeAll: { router.show(.transactions) },
                        onAdd: { router.addEntry() }
                    )
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, DS.Spacing.s)
                .padding(.bottom, 96)
                .animation(DS.Motion.adaptive(DS.Motion.spring), value: hasDemoData)
            }
            .background(DS.Colors.background)
            .navigationTitle(period.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                ForEach(recentMonths, id: \.start) { month in
                    Button {
                        select(month)
                    } label: {
                        if month == period {
                            Label(month.title, systemImage: "checkmark")
                        } else {
                            Text(month.title)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !period.isCurrent {
                        Button("Today") { select(.month()) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AccountsListView()
                    } label: {
                        Image(systemName: "wallet.pass")
                    }
                    .accessibilityLabel(Text("Accounts"))
                }
            }
            .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
            .navigationDestination(for: LedgerEntry.self) { TransactionDetailView(entry: $0) }
            .overlay(alignment: .bottomTrailing) {
                FloatingAddButton(onSelectKind: { router.addEntry($0) }) { router.addEntry() }
                    .padding(.trailing, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.l)
            }
            .confirmationDialog("Remove demo data?", isPresented: $confirmClearDemo, titleVisibility: .visible) {
                Button("Remove Demo Data", role: .destructive) {
                    withMotion { LedgerStore(context: context).deleteDemoData() }
                    Haptics.success()
                }
            } message: {
                Text("Demo accounts, their transactions, demo tags and budgets will be deleted. Your own records are kept.")
            }
        }
    }

    private var recentMonths: [Period] {
        (0..<24).map { Period.month().shifted(by: -$0) }
    }

    private func select(_ month: Period) {
        Haptics.selection()
        withMotion { period = month }
    }

    private func shift(_ delta: Int) {
        let target = period.shifted(by: delta)
        guard !target.isFuture else { Haptics.warning(); return }
        select(target)
    }

    private func makeSnapshot(math: LedgerMath) -> DashboardSnapshot {
        var s = DashboardSnapshot()
        let previous = period.previous
        var monthEntries: [LedgerEntry] = []
        var previousEntries: [LedgerEntry] = []
        for e in entries {
            if period.contains(e.date) { monthEntries.append(e) }
            else if previous.contains(e.date) { previousEntries.append(e) }
        }
        s.summary = math.summary(monthEntries)
        let comparableEnd = period.comparableEnd(in: previous)
        s.previousSummary = math.summary(previousEntries.filter { $0.date < comparableEnd })
        s.balances = math.balances(accounts: accounts, entries: entries)
        s.netWorth = math.netWorth(accounts: accounts, balances: s.balances)
        s.thisMonthSeries = math.cumulativeSeries(monthEntries, period: period, kind: .expense)
        s.lastMonthSeries = math.cumulativeSeries(previousEntries, period: previous, kind: .expense)
        s.recent = Array(monthEntries.prefix(6))
        for e in s.recent { s.values[e.id] = math.value(e) }
        s.budget = BudgetEvaluator(math: math).overview(budgets: budgets, entries: monthEntries, period: period)
        return s
    }
}

private struct DemoBanner: View {
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            Image(systemName: "sparkles")
                .foregroundStyle(DS.Colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Demo data").font(.subheadline.weight(.semibold))
                Text("Sample records for exploring Tally.").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove", action: onClear)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        }
        .card(padding: 14, radius: DS.Radius.inner + 4)
    }
}
