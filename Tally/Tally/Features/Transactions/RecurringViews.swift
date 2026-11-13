import SwiftUI
import SwiftData

/// Recurring plans. Plans never change balances; each occurrence is booked as a real
/// transaction once its date arrives (at launch and when Tally returns to the foreground).
struct RecurringListView: View {
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \RecurringRule.nextDate) private var rules: [RecurringRule]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @State private var editor: RuleEditorRequest?

    var body: some View {
        List {
            Section {
                ForEach(rules) { rule in
                    Button { editor = RuleEditorRequest(rule: rule) } label: { RuleRow(rule: rule, accounts: accounts) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                context.delete(rule)
                                try? context.save()
                            } label: { Label("Delete", systemImage: "trash") }
                            Button {
                                rule.isActive.toggle()
                                try? context.save()
                            } label: {
                                Label(rule.isActive ? String(localized: "Pause") : String(localized: "Resume"),
                                      systemImage: rule.isActive ? "pause" : "play")
                            }
                            .tint(.gray)
                        }
                }
            } footer: {
                Text("Due occurrences are booked automatically when Tally opens. Future occurrences never affect balances, and each occurrence is booked only once.")
            }
        }
        .listStyle(.insetGrouped)
        .pageBackground()
        .navigationTitle("Recurring Plans")
        .overlay {
            if rules.isEmpty {
                ContentUnavailableView {
                    Label("No Recurring Plans", systemImage: "repeat")
                } description: {
                    Text("Add rent, salary, subscriptions or regular transfers.")
                } actions: {
                    Button("Add Plan") { editor = RuleEditorRequest(rule: nil) }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = RuleEditorRequest(rule: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text("Add Plan"))
            }
        }
        .sheet(item: $editor, onDismiss: postDue) { request in
            RecurringEditorSheet(rule: request.rule)
        }
    }

    private func postDue() {
        let result = RecurringService(context: context).postDueOccurrences()
        if result.posted > 0 {
            toasts.show(ToastMessage(symbol: "repeat", text: String(localized: "\(result.posted) recurring transactions booked"), style: .success))
        }
    }
}

struct RuleEditorRequest: Identifiable {
    let id = UUID()
    var rule: RecurringRule?
}

private struct RuleRow: View {
    let rule: RecurringRule
    let accounts: [Account]

    var body: some View {
        let account = accounts.first { $0.id == rule.accountID }
        HStack(spacing: DS.Spacing.m) {
            SymbolBadge(symbol: rule.kind.symbol, colorHex: rule.isActive ? "3E7BFA" : "8E8E93", size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(.body.weight(.medium))
                Text(verbatim: summary + (account.map { " · " + $0.name } ?? ""))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(MoneyFormat.signed(rule.amount, code: account?.currencyCode ?? AppSettings.baseCurrency, kind: rule.kind))
                    .font(DS.Typography.rowAmount).monospacedDigit()
                Text(rule.isActive ? rule.nextDate.shortDateText : String(localized: "Paused"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var summary: String {
        rule.frequency.everyText(rule.interval)
    }
}

struct RecurringEditorSheet: View {
    let rule: RecurringRule?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var name = ""
    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var toAccountID: UUID?
    @State private var categoryID: UUID?
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var interval = 1
    @State private var startDate = Date.now
    @State private var hasEnd = false
    @State private var endDate = Calendar.ledger.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var note = ""
    @State private var loaded = false

    private var active: [Account] { accounts.filter { !$0.isArchived } }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let amount = DecimalCodec.parseLenient(amountText), amount > 0,
              accountID != nil else { return false }
        if kind == .transfer { return toAccountID != nil && toAccountID != accountID }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Rent)", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(TransactionKind.primary) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }
                Section {
                    Picker(kind == .transfer ? String(localized: "From") : String(localized: "Account"), selection: $accountID) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(active) { a in Text(verbatim: a.name + " · " + a.currencyCode).tag(UUID?.some(a.id)) }
                    }
                    if kind == .transfer {
                        Picker("To", selection: $toAccountID) {
                            Text("Choose").tag(UUID?.none)
                            ForEach(active.filter { $0.id != accountID }) { a in Text(verbatim: a.name + " · " + a.currencyCode).tag(UUID?.some(a.id)) }
                        }
                    } else {
                        Picker("Category", selection: $categoryID) {
                            Text("Uncategorized").tag(UUID?.none)
                            ForEach(categories.filter { $0.kind == (kind.categoryKind ?? .expense) && !$0.isArchived }) { c in
                                Label(c.name, systemImage: c.symbolName).tag(UUID?.some(c.id))
                            }
                        }
                    }
                }
                Section("Schedule") {
                    Picker("Repeats", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper(value: $interval, in: 1...52) {
                        Text(verbatim: frequency.everyText(interval))
                    }
                    DatePicker("First date", selection: $startDate)
                        .disabled(rule != nil && (rule?.generatedCount ?? 0) > 0)
                    Toggle("End date", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }
                Section {
                    TextField("Note", text: $note)
                }
            }
            .navigationTitle(rule == nil ? String(localized: "New Plan") : String(localized: "Edit Plan"))
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).disabled(!canSave)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let rule {
            name = rule.name
            kind = rule.kind
            amountText = DecimalCodec.encode(rule.amount)
            accountID = rule.accountID
            toAccountID = rule.toAccountID
            categoryID = rule.categoryID
            frequency = rule.frequency
            interval = rule.interval
            startDate = rule.startDate
            hasEnd = rule.endDate != nil
            endDate = rule.endDate ?? endDate
            note = rule.note
        } else {
            accountID = AppSettings.uuid(forKey: SettingsKey.defaultAccountID) ?? active.first?.id
        }
    }

    private func save() {
        guard let amount = DecimalCodec.parseLenient(amountText), amount > 0 else { return }
        let target: RecurringRule
        if let rule {
            target = rule
        } else {
            target = RecurringRule(name: name, kind: kind, amount: amount, frequency: frequency, interval: interval, startDate: startDate)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.kind = kind
        target.amount = amount
        target.accountID = accountID
        target.toAccountID = kind == .transfer ? toAccountID : nil
        target.categoryID = kind == .transfer ? nil : categoryID
        target.frequency = frequency
        target.interval = interval
        if target.generatedCount == 0 { target.startDate = startDate }
        target.endDate = hasEnd ? endDate : nil
        target.note = note
        target.nextDate = Recurrence.occurrence(target.generatedCount, start: target.startDate, frequency: frequency, interval: interval)
        target.isActive = true
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
