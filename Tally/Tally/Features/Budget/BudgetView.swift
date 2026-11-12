import SwiftUI
import SwiftData

struct BudgetView: View {
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @Query private var rates: [ExchangeRate]

    @State private var period = Period.month()
    @State private var editor: BudgetEditorRequest?

    var body: some View {
        let math = LedgerMath(base: baseCurrency, rates: rates)
        let monthEntries = entries.filter { period.contains($0.date) }
        let overview = BudgetEvaluator(math: math).overview(budgets: budgets, entries: monthEntries, period: period)

        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.l) {
                    monthSwitcher

                    if let overall = overview.overall {
                        OverallBudgetCard(status: overall, period: period, base: baseCurrency) {
                            editor = BudgetEditorRequest(budget: overall.budget)
                        }
                    } else {
                        EmptyBudgetCard { editor = BudgetEditorRequest(budget: nil, isOverall: true) }
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.m) {
                        SectionHeader("Categories") {
                            Button {
                                editor = BudgetEditorRequest(budget: nil, isOverall: false)
                            } label: {
                                Label("Add", systemImage: "plus")
                            }
                        }

                        if overview.categories.isEmpty {
                            Text("Give a category its own limit to keep an eye on it.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .card()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(overview.categories.enumerated()), id: \.element.id) { index, status in
                                    Button {
                                        editor = BudgetEditorRequest(budget: status.budget)
                                    } label: {
                                        CategoryBudgetRow(status: status, base: baseCurrency)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button { editor = BudgetEditorRequest(budget: status.budget) } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            withMotion {
                                                context.delete(status.budget)
                                                try? context.save()
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    if index < overview.categories.count - 1 {
                                        Divider().padding(.leading, 62)
                                    }
                                }
                            }
                            .background(DS.Colors.card, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        }
                    }

                    Text("Budgets repeat every month. Reminders appear quietly inside the app once per budget when you approach or pass a limit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Spacing.xs)
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.bottom, DS.Spacing.xxl)
                .animation(DS.Motion.adaptive(DS.Motion.spring), value: budgets.count)
            }
            .background(DS.Colors.background)
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = BudgetEditorRequest(budget: nil, isOverall: overview.overall == nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Add budget"))
                }
            }
            .sheet(item: $editor) { request in
                BudgetEditorSheet(request: request)
            }
        }
    }

    private var monthSwitcher: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 36, height: 36)
            }
            .accessibilityLabel(Text("Previous month"))
            Spacer()
            Text(period.title).font(.headline)
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 36, height: 36)
            }
            .disabled(period.next.isFuture)
            .accessibilityLabel(Text("Next month"))
        }
        .padding(.top, DS.Spacing.xs)
    }

    private func shift(_ delta: Int) {
        let target = period.shifted(by: delta)
        guard !target.isFuture else { return }
        Haptics.selection()
        withMotion { period = target }
    }
}

struct BudgetEditorRequest: Identifiable {
    let id = UUID()
    var budget: Budget?
    var isOverall: Bool = false

    init(budget: Budget?, isOverall: Bool? = nil) {
        self.budget = budget
        self.isOverall = isOverall ?? (budget?.isOverall ?? false)
    }
}

private struct OverallBudgetCard: View {
    let status: BudgetStatus
    let period: Period
    let base: String
    var onEdit: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            HStack {
                Text("Monthly budget").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button("Edit", action: onEdit).font(.subheadline.weight(.medium))
            }

            ZStack {
                RingProgress(fraction: status.fraction, tint: DS.Colors.budget(status.level), lineWidth: 14)
                    .frame(width: 180, height: 180)
                VStack(spacing: 4) {
                    Group {
                        if status.remaining >= 0 { Text("Left") } else { Text("Over") }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    AmountText(value: status.remaining.magnitudeValue, code: base, font: DS.Typography.cardAmount,
                               color: status.level == .exceeded ? DS.Colors.danger : .primary)
                    Text(MoneyFormat.percent(status.fraction))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Colors.budget(status.level))
                }
                .frame(width: 140)
            }
            .accessibilityElement(children: .combine)

            HStack {
                metric("Spent", MoneyFormat.string(status.spent, code: base))
                metric("Budget", MoneyFormat.string(status.limit, code: base))
                if let daily = BudgetEvaluator.dailyAllowance(for: status, period: period) {
                    metric("Per day", MoneyFormat.string(daily, code: base))
                } else {
                    metric("Days", "\(period.dayCount)")
                }
            }

            if status.level != .normal {
                HStack(spacing: 8) {
                    Image(systemName: status.level == .exceeded ? "exclamationmark.circle" : "leaf")
                    Group {
                        if status.level == .exceeded {
                            Text("You've gone past this month's budget. It resets on the 1st.")
                        } else {
                            Text("You're close to this month's budget — a little restraint goes a long way.")
                        }
                    }
                }
                .font(.footnote)
                .foregroundStyle(DS.Colors.budget(status.level))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card(padding: DS.Spacing.xl)
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct EmptyBudgetCard: View {
    var onCreate: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.m) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 40))
                .foregroundStyle(DS.Colors.accent)
            Text("Set a monthly budget").font(.headline)
            Text("Tally tracks it in real time and lets you know gently when you get close.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Create Budget", action: onCreate)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity)
        .card(padding: DS.Spacing.xxl)
    }
}

private struct CategoryBudgetRow: View {
    let status: BudgetStatus
    let base: String

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            SymbolBadge(symbol: status.symbolName, colorHex: status.colorHex, size: 38)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(status.title).font(.body.weight(.medium))
                    Spacer()
                    Text("\(MoneyFormat.string(status.spent, code: base)) / \(MoneyFormat.string(status.limit, code: base))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                CapsuleProgress(fraction: status.fraction, tint: DS.Colors.budget(status.level))
                Group {
                    if status.remaining >= 0 {
                        Text("\(MoneyFormat.string(status.remaining, code: base)) left")
                    } else {
                        Text("\(MoneyFormat.string(-status.remaining, code: base)) over")
                    }
                }
                .font(.caption)
                .foregroundStyle(status.level == .normal ? Color.secondary : DS.Colors.budget(status.level))
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
