import SwiftUI
import SwiftData

struct BudgetEditorRequest: Identifiable {
    let id = UUID()
    var budget: Budget?
    var overall: Bool
}

struct BudgetEditorSheet: View {
    let request: BudgetEditorRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @AppStorage(SettingsKey.budgetStartDay) private var startDay = 1
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query private var budgets: [Budget]

    @State private var amountText = ""
    @State private var currency = AppSettings.baseCurrency
    @State private var categoryID: UUID?
    @State private var period: BudgetPeriodKind = .monthly
    @State private var customDays = 30
    @State private var anchor = Calendar.ledger.startOfDay(for: .now)
    @State private var rollover = false
    @State private var threshold = 0.8
    @State private var excluded: Set<UUID> = []
    @State private var loaded = false
    @State private var errorText: String?
    @State private var confirmDelete = false

    private var isOverall: Bool { request.overall }
    private var expenseCategories: [LedgerCategory] { categories.filter { $0.kind == .expense && !$0.isArchived } }

    private var amount: Decimal? {
        guard let v = DecimalCodec.parseLenient(amountText), v > 0 else { return nil }
        return v.rounded(scale: CurrencyInfo.info(for: currency).fractionDigits)
    }

    /// Another budget already covers the same scope and period kind.
    private var duplicate: Budget? {
        budgets.first { b in
            b.id != request.budget?.id && b.periodKind == period
                && (isOverall ? b.isOverall : b.category?.id == categoryID)
        }
    }

    private var canSave: Bool {
        amount != nil && duplicate == nil && (isOverall || categoryID != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold).monospacedDigit())
                        Picker("Currency", selection: $currency) {
                            ForEach(CurrencyInfo.all) { Text($0.code).tag($0.code) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    if !isOverall {
                        Picker("Category", selection: $categoryID) {
                            Text("Choose…").tag(UUID?.none)
                            ForEach(expenseCategories) { c in
                                Label(c.name, systemImage: c.symbolName).tag(UUID?.some(c.id))
                            }
                        }
                    }
                } header: {
                    Text(isOverall ? "Overall Budget" : "Category Budget")
                } footer: {
                    if currency != baseCurrency {
                        Text("Progress is shown in \(baseCurrency), converting this limit at the latest rate.")
                    } else if duplicate != nil {
                        Text("A budget with the same scope and period already exists.")
                            .foregroundStyle(DS.Colors.danger)
                    }
                }

                Section {
                    Picker("Period", selection: $period) {
                        ForEach(BudgetPeriodKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if period == .custom {
                        Stepper(value: $customDays, in: 1...366) {
                            LabeledContent("Length", value: String(localized: "\(customDays) days"))
                        }
                        DatePicker("First period starts", selection: $anchor, displayedComponents: .date)
                    }
                } footer: {
                    switch period {
                    case .monthly: Text("Monthly periods start on day \(startDay). Change this in Settings › Finance.")
                    case .weekly: Text("Weeks start on Monday.")
                    case .yearly: Text("Calendar years.")
                    case .custom: Text("Repeats every \(customDays) days from the start date.")
                    }
                }

                Section {
                    Toggle("Roll over", isOn: $rollover)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Alert at")
                            Spacer()
                            Text(MoneyFormat.percent(threshold)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $threshold, in: 0.5...1.0, step: 0.05)
                    }
                } footer: {
                    Text("Roll over carries what's left (or overspent) into the next period. Alerts appear when spending passes the threshold.")
                }

                if isOverall {
                    Section {
                        NavigationLink {
                            ExcludedCategoriesPicker(categories: expenseCategories, excluded: $excluded)
                        } label: {
                            LabeledContent("Exclude Categories", value: excluded.isEmpty ? String(localized: "None") : excluded.count.formatted())
                        }
                    } footer: {
                        Text("Excluded categories don't count toward this budget — useful for rent or one-off purchases.")
                    }
                }

                if request.budget != nil {
                    Section {
                        Button("Delete Budget", role: .destructive) { confirmDelete = true }
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(DS.Colors.danger) }
                }
            }
            .navigationTitle(request.budget == nil ? String(localized: "New Budget") : String(localized: "Edit Budget"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this budget?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Budget", role: .destructive) {
                    guard let budget = request.budget else { return }
                    do {
                        try LedgerRepository(context: context).deleteBudget(budget)
                        Haptics.success()
                        dismiss()
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
            } message: {
                Text("Transactions are not affected.")
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(hasChanges)
        .onAppear(perform: load)
    }

    private var hasChanges: Bool {
        guard let b = request.budget else { return !amountText.isEmpty }
        return amount != b.amount || currency != b.currencyCode || period != b.periodKind
            || rollover != b.rollover || threshold != b.alertThreshold || excluded != b.excludedCategoryIDs
            || categoryID != b.category?.id
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        currency = baseCurrency
        guard let b = request.budget else { return }
        amountText = DecimalCodec.encode(b.amount)
        currency = b.currencyCode
        categoryID = b.category?.id
        period = b.periodKind
        customDays = b.customLengthDays
        anchor = b.anchorDate
        rollover = b.rollover
        threshold = b.alertThreshold
        excluded = b.excludedCategoryIDs
    }

    private func save() {
        guard let amount else { return }
        let draft = LedgerRepository.BudgetDraft(
            amount: amount,
            currencyCode: currency,
            category: isOverall ? nil : categories.first { $0.id == categoryID },
            threshold: threshold,
            period: period,
            customLengthDays: customDays,
            anchorDate: anchor,
            rollover: rollover,
            excluded: isOverall ? excluded : []
        )
        do {
            try LedgerRepository(context: context).saveBudget(draft, editing: request.budget)
            Haptics.success()
            toasts.show(ToastMessage(symbol: "checkmark.circle.fill", text: String(localized: "Budget saved"), style: .success))
            dismiss()
        } catch {
            Haptics.error()
            errorText = error.localizedDescription
        }
    }
}

private struct ExcludedCategoriesPicker: View {
    let categories: [LedgerCategory]
    @Binding var excluded: Set<UUID>

    var body: some View {
        List {
            Section {
                ForEach(categories) { c in
                    Button {
                        Haptics.selection()
                        if excluded.contains(c.id) { excluded.remove(c.id) } else { excluded.insert(c.id) }
                    } label: {
                        HStack(spacing: DS.Spacing.m) {
                            SymbolBadge(symbol: c.symbolName, colorHex: c.colorHex, size: 30)
                            Text(c.name).foregroundStyle(.primary)
                            Spacer()
                            if excluded.contains(c.id) {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(DS.Colors.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(excluded.contains(c.id) ? .isSelected : [])
                }
            } footer: {
                Text("Checked categories are not counted in the overall budget.")
            }
        }
        .navigationTitle("Exclude Categories")
        .navigationBarTitleDisplayMode(.inline)
    }
}
