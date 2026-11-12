import SwiftUI
import SwiftData

/// Spending limits per period. Overall budgets first, then per-category budgets
/// (switching to a compact list when there are many).
struct BudgetsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LedgerCache.self) private var cache
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @AppStorage(SettingsKey.budgetStartDay) private var startDay = 1
    @AppStorage("budgets.compact") private var compactPreference = false

    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var statuses: [UUID: BudgetStatus] = [:]
    @State private var editor: BudgetEditorRequest?
    @State private var pendingDelete: Budget?

    private var overall: [Budget] { budgets.filter(\.isOverall) }
    private var byCategory: [Budget] {
        budgets.filter { !$0.isOverall }.sorted { a, b in
            (a.category?.sortOrder ?? 0) < (b.category?.sortOrder ?? 0)
        }
    }

    /// Many category budgets read better as a dense list.
    private var compact: Bool { compactPreference || byCategory.count > 6 }

    private var taskKey: String { "\(cache.version)|\(baseCurrency)|\(startDay)|\(budgets.count)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.l) {
                    if budgets.isEmpty {
                        emptyState
                    } else {
                        ForEach(overall) { budget in
                            OverallBudgetCard(budget: budget, status: statuses[budget.id], base: baseCurrency, categories: categories)
                                .onTapGesture { showTransactions(budget) }
                                .contextMenu { menu(for: budget) }
                        }
                        if overall.isEmpty {
                            AddOverallCard { editor = BudgetEditorRequest(budget: nil, overall: true) }
                        }
                        categorySection
                    }
                    footnote
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.bottom, DS.Spacing.xxl)
                .animation(DS.Motion.adaptive(DS.Motion.spring), value: statuses)
            }
            .background(PageBackground())
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { editor = BudgetEditorRequest(budget: nil, overall: true) } label: {
                            Label("Overall Budget", systemImage: "chart.pie")
                        }
                        Button { editor = BudgetEditorRequest(budget: nil, overall: false) } label: {
                            Label("Category Budget", systemImage: "square.grid.2x2")
                        }
                        Divider()
                        Toggle(isOn: $compactPreference) { Label("Compact List", systemImage: "list.bullet") }
                    } label: {
                        Image(systemName: "plus").font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(Text("Add Budget"))
                }
            }
            .task(id: taskKey) { await recompute() }
            .sheet(item: $editor) { request in
                BudgetEditorSheet(request: request)
            }
            .confirmationDialog("Delete this budget?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Budget", role: .destructive) {
                    if let budget = pendingDelete {
                        try? LedgerRepository(context: context).deleteBudget(budget)
                        Haptics.success()
                    }
                    pendingDelete = nil
                }
            } message: {
                Text("Transactions are not affected.")
            }
        }
    }

    // MARK: Sections

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.m) {
            Image(systemName: "chart.pie").font(.system(size: 44)).foregroundStyle(DS.Colors.accent)
            Text("No Budgets").font(.title3.weight(.semibold))
            Text("Set a monthly limit for all spending, then add limits for the categories you want to watch.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Set Monthly Budget") { editor = BudgetEditorRequest(budget: nil, overall: true) }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .padding(.top, DS.Spacing.s)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xxl)
        .card(padding: DS.Spacing.xl)
        .padding(.top, DS.Spacing.l)
    }

    @ViewBuilder
    private var categorySection: some View {
        let list = byCategory
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack {
                Text("Category Budgets").font(DS.Typography.sectionTitle)
                Spacer()
                Button { editor = BudgetEditorRequest(budget: nil, overall: false) } label: {
                    Label("Add", systemImage: "plus").font(.subheadline.weight(.medium))
                }
            }
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.top, DS.Spacing.s)

            if list.isEmpty {
                Text("Add a limit for a category such as Dining or Shopping to track it separately.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, budget in
                        Button { showTransactions(budget) } label: {
                            CategoryBudgetRow(budget: budget, status: statuses[budget.id], base: baseCurrency, compact: compact)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(for: budget) }
                        if index < list.count - 1 { Divider().padding(.leading, compact ? 44 : 56) }
                    }
                }
                .card(padding: compact ? DS.Spacing.m : DS.Spacing.l)
            }
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Budgets count expenses net of refunds, plus transfer fees. Transfers, card repayments and balance adjustments don't count.")
            if startDay != 1 {
                Text("Monthly budgets start on day \(startDay) of each month.")
            }
            Text("Long-press a budget to edit or delete it. Tap to see its transactions.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.xs)
    }

    @ViewBuilder
    private func menu(for budget: Budget) -> some View {
        Button { editor = BudgetEditorRequest(budget: budget, overall: budget.isOverall) } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button { showTransactions(budget) } label: {
            Label("Show Transactions", systemImage: "list.bullet.rectangle")
        }
        Button(role: .destructive) { pendingDelete = budget } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: Actions

    private func showTransactions(_ budget: Budget) {
        guard let status = statuses[budget.id] else { return }
        Haptics.selection()
        let period = Period(customFrom: status.period.start, through: status.period.end.addingTimeInterval(-1))
        router.showTransactions(TransactionQuery(period: period, categoryID: budget.category?.id,
                                                 kinds: [.expense, .refund, .transfer]))
    }

    private func recompute() async {
        let base = baseCurrency
        let day = startDay
        let result = await cache.compute("budgets|\(base)|\(day)") { snapshot, converter in
            let engine = BudgetEngine(finance: FinanceEngine(base: base, converter: converter), monthStartDay: day)
            var out: [UUID: BudgetStatus] = [:]
            for b in snapshot.budgets { out[b.id] = engine.status(of: b, entries: snapshot.entries) }
            return out
        }
        statuses = result
    }
}

// MARK: - Overall card

private struct OverallBudgetCard: View {
    let budget: Budget
    let status: BudgetStatus?
    let base: String
    let categories: [LedgerCategory]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(BudgetTitle.overall(budget.periodKind)).font(.headline)
                    if let status {
                        Text(BudgetTitle.interval(status.period)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if budget.currencyCode != base {
                    Text(verbatim: MoneyFormat.string(budget.amount, code: budget.currencyCode))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let status {
                HStack(spacing: DS.Spacing.xl) {
                    ZStack {
                        RingProgress(fraction: status.fraction, tint: DS.Colors.budget(status.level), lineWidth: 12)
                        VStack(spacing: 0) {
                            Text(MoneyFormat.percent(status.fraction))
                                .font(.title3.weight(.semibold).monospacedDigit())
                            Text("used").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 104, height: 104)

                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        if status.spent > status.limit {
                            Text("Overspent").font(.footnote).foregroundStyle(.secondary)
                            AmountText(value: status.overspent, code: base, font: DS.Typography.cardAmount, color: DS.Colors.danger)
                        } else {
                            Text("Remaining").font(.footnote).foregroundStyle(.secondary)
                            AmountText(value: status.remaining, code: base, font: DS.Typography.cardAmount)
                        }
                        Text("\(MoneyFormat.string(status.spent, code: base)) of \(MoneyFormat.string(status.limit, code: base))")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                BudgetFacts(status: status, base: base)

                if let note = notes(status) {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 104)
            }
        }
        .card(padding: DS.Spacing.xl)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows the transactions in this budget"))
    }

    private func notes(_ status: BudgetStatus) -> String? {
        var lines: [String] = []
        if status.carried > 0 {
            lines.append(String(localized: "Includes \(MoneyFormat.string(status.carried, code: base)) left over from earlier periods."))
        } else if status.carried < 0 {
            lines.append(String(localized: "Reduced by \(MoneyFormat.string(-status.carried, code: base)) overspent in earlier periods."))
        }
        let excluded = budget.excludedCategoryIDs
        if !excluded.isEmpty {
            let names = categories.filter { excluded.contains($0.id) }.map(\.name)
            lines.append(String(localized: "Not counting: \(names.joined(separator: ", "))"))
        }
        lines.append(contentsOf: BudgetTitle.warnings(status, budget: budget, base: base))
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

private struct BudgetFacts: View {
    let status: BudgetStatus
    let base: String

    var body: some View {
        HStack(spacing: 0) {
            fact("Days left", Text(status.daysRemaining.formatted()))
            Divider().frame(height: 28)
            fact("Per day", Text(status.dailyAllowance.map { MoneyFormat.string($0, code: base) } ?? "—"))
            Divider().frame(height: 28)
            fact("Alert at", Text(MoneyFormat.percent(status.threshold)))
        }
        .padding(.vertical, DS.Spacing.s)
        .background(DS.Colors.fill.opacity(0.6), in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
    }

    private func fact(_ title: LocalizedStringKey, _ value: Text) -> some View {
        VStack(spacing: 2) {
            value.font(.subheadline.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AddOverallCard: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.m) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(DS.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set an overall budget").font(.subheadline.weight(.semibold))
                    Text("A limit for all spending in a month, week or year.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .card()
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Category row

private struct CategoryBudgetRow: View {
    let budget: Budget
    let status: BudgetStatus?
    let base: String
    let compact: Bool

    private var name: String { budget.category?.name ?? String(localized: "Uncategorized") }
    private var symbol: String { budget.category?.symbolName ?? "questionmark" }
    private var color: String { budget.category?.colorHex ?? "8E8E93" }

    var body: some View {
        Group {
            if compact { compactBody } else { fullBody }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var tint: Color { status.map { DS.Colors.budget($0.level) } ?? DS.Colors.accent }

    private var fullBody: some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            SymbolBadge(symbol: symbol, colorHex: color, size: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(.subheadline.weight(.semibold))
                    if budget.periodKind != .monthly {
                        Text(budget.periodKind.title).font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(DS.Colors.fill, in: Capsule())
                    }
                    Spacer()
                    if let status {
                        if status.spent > status.limit {
                            Text("Over \(MoneyFormat.string(status.overspent, code: base))")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(DS.Colors.danger)
                        } else {
                            Text("\(MoneyFormat.string(status.remaining, code: base)) left")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                    }
                }
                CapsuleProgress(fraction: status?.fraction ?? 0, tint: tint, height: 6)
                if let status {
                    HStack {
                        Text("\(MoneyFormat.string(status.spent, code: base)) of \(MoneyFormat.string(status.limit, code: base))")
                        Spacer()
                        if let daily = status.dailyAllowance {
                            Text("\(MoneyFormat.string(daily, code: base))/day · \(status.daysRemaining) days")
                        } else if status.daysRemaining > 0 {
                            Text("\(status.daysRemaining) days left")
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    ForEach(BudgetTitle.warnings(status, budget: budget, base: base), id: \.self) { line in
                        Text(line).font(.caption2).foregroundStyle(DS.Colors.warning)
                    }
                }
            }
        }
        .padding(.vertical, DS.Spacing.s)
    }

    private var compactBody: some View {
        HStack(spacing: DS.Spacing.m) {
            SymbolBadge(symbol: symbol, colorHex: color, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
                    Spacer()
                    if let status {
                        Text(MoneyFormat.percent(status.fraction))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(tint)
                        Group {
                            if status.spent > status.limit {
                                Text("−" + MoneyFormat.string(status.overspent, code: base)).foregroundStyle(DS.Colors.danger)
                            } else {
                                Text(MoneyFormat.string(status.remaining, code: base))
                            }
                        }
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 70, alignment: .trailing)
                    }
                }
                CapsuleProgress(fraction: status?.fraction ?? 0, tint: tint, height: 4)
            }
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Shared text

enum BudgetTitle {
    static func overall(_ kind: BudgetPeriodKind) -> String {
        switch kind {
        case .monthly: String(localized: "Monthly Budget")
        case .weekly: String(localized: "Weekly Budget")
        case .yearly: String(localized: "Yearly Budget")
        case .custom: String(localized: "Custom Budget")
        }
    }

    static func interval(_ interval: DateInterval) -> String {
        Date.rangeText(interval.start, interval.end.addingTimeInterval(-1))
    }

    static func warnings(_ status: BudgetStatus, budget: Budget, base: String) -> [String] {
        var lines: [String] = []
        if status.limitPending {
            lines.append(String(localized: "No exchange rate from \(budget.currencyCode) to \(base); add one to track this budget."))
        }
        if status.pendingCount > 0 {
            lines.append(String(localized: "\(status.pendingCount) transactions are waiting for an exchange rate and are not counted."))
        }
        return lines
    }
}
