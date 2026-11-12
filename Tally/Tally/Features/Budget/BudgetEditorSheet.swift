import SwiftUI
import SwiftData

struct BudgetEditorSheet: View {
    let request: BudgetEditorRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var rates: [ExchangeRate]

    @State private var isOverall = true
    @State private var categoryID: UUID?
    @State private var amountText = ""
    @State private var threshold = 0.8
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool

    private var availableCategories: [LedgerCategory] {
        let taken = Set(budgets.compactMap { $0.category?.id }).subtracting([request.budget?.category?.id].compactMap { $0 })
        return categories.filter { $0.kind == .expense && !$0.isArchived && !taken.contains($0.id) }
    }

    private var hasOverall: Bool {
        budgets.contains { $0.isOverall && $0.id != request.budget?.id }
    }

    private var amount: Decimal? { DecimalCodec.parseLenient(amountText) }

    private var canSave: Bool {
        guard let amount, amount > 0 else { return false }
        return isOverall ? !hasOverall : categoryID != nil
    }

    /// Average monthly spending over the previous three full months.
    private var suggestion: Decimal? {
        let math = LedgerMath(base: baseCurrency, rates: rates)
        let current = Period.month()
        let months = (1...3).map { current.shifted(by: -$0) }
        let start = months.last?.start ?? current.start
        let relevant = entries.filter { e in
            e.kind == .expense && e.date >= start && e.date < current.start
                && (isOverall || e.category?.id == categoryID)
        }
        guard !relevant.isEmpty else { return nil }
        let total = relevant.sum { math.value($0) }
        return (total / 3).rounded(scale: 0, mode: .up)
    }

    var body: some View {
        NavigationStack {
            Form {
                if request.budget == nil {
                    Section {
                        Picker("Budget type", selection: $isOverall) {
                            Text("Overall").tag(true)
                            Text("Category").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                if !isOverall {
                    Section("Category") {
                        if availableCategories.isEmpty {
                            Text("Every expense category already has a budget.").foregroundStyle(.secondary)
                        } else {
                            Picker("Category", selection: $categoryID) {
                                Text("Choose").tag(UUID?.none)
                                ForEach(availableCategories) { c in
                                    Label(c.name, systemImage: c.symbolName).tag(UUID?.some(c.id))
                                }
                            }
                        }
                    }
                } else if hasOverall {
                    Section {
                        Label("An overall budget already exists. Edit it from the Budget tab.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Text(CurrencyInfo.info(for: baseCurrency).symbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Amount", text: $amountText)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                    }
                    if let suggestion, suggestion > 0 {
                        Button {
                            Haptics.selection()
                            amountText = DecimalCodec.encode(suggestion)
                        } label: {
                            Label("Use 3-month average: \(MoneyFormat.string(suggestion, code: baseCurrency))", systemImage: "wand.and.stars")
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("Monthly limit")
                } footer: {
                    Text("Amounts are in your main currency (\(baseCurrency)).")
                }

                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Remind me at")
                            Spacer()
                            Text(MoneyFormat.percent(threshold)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $threshold, in: 0.5...1.0, step: 0.05)
                    }
                } footer: {
                    Text("A single, quiet in-app reminder appears when spending reaches this share of the budget.")
                }

                if request.budget != nil {
                    Section {
                        Button("Delete Budget", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(request.budget == nil ? String(localized: "New Budget") : String(localized: "Edit Budget"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this budget?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let budget = request.budget {
                        context.delete(budget)
                        try? context.save()
                    }
                    Haptics.success()
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    private func load() {
        isOverall = request.isOverall
        if let budget = request.budget {
            categoryID = budget.category?.id
            let converter = CurrencyConverter(rates: rates)
            let value = converter.convertOrSame(budget.amount, from: budget.currencyCode, to: baseCurrency)
            amountText = DecimalCodec.encode(value)
            threshold = budget.alertThreshold
        } else if !isOverall {
            categoryID = availableCategories.first?.id
        }
        if request.budget == nil { amountFocused = true }
    }

    private func save() {
        guard let amount, amount > 0 else { return }
        let category = isOverall ? nil : categories.first { $0.id == categoryID }
        LedgerStore(context: context).setBudget(amount: amount, category: category, threshold: threshold, editing: request.budget)
        Haptics.success()
        dismiss()
    }
}
