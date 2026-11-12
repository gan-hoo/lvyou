import SwiftUI
import SwiftData

/// Bottom sheet for recording or editing an entry.
struct QuickEntrySheet: View {
    let request: EntryRequest

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @State private var model: QuickEntryViewModel?

    var body: some View {
        Group {
            if let model {
                QuickEntryContent(model: model, accounts: accounts.filter { !$0.isArchived }, categories: categories)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil {
                model = QuickEntryViewModel(request: request, accounts: accounts, categories: categories)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(DS.Colors.background)
    }
}

private struct QuickEntryContent: View {
    @Bindable var model: QuickEntryViewModel
    var accounts: [Account]
    var categories: [LedgerCategory]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var rates: [ExchangeRate]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]

    @State private var showDatePicker = false
    @State private var showTags = false
    @State private var showCategories = false
    @State private var confirmDelete = false
    @State private var shakeAmount = 0
    @FocusState private var focus: Field?

    private enum Field { case note, credited }

    private var tint: Color {
        switch model.kind {
        case .expense: DS.Colors.accent
        case .income: DS.Colors.income
        case .transfer: DS.Colors.transfer
        }
    }

    private var visibleCategories: [LedgerCategory] {
        guard let kind = model.kind.categoryKind else { return [] }
        return categories.filter { $0.kind == kind && !$0.isArchived }
    }

    private var converter: CurrencyConverter { CurrencyConverter(rates: rates) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, 18)

            amountDisplay
                .padding(.horizontal, DS.Spacing.screen + 4)
                .padding(.top, DS.Spacing.l)

            noteField
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, DS.Spacing.s)

            ScrollView {
                Group {
                    if model.kind == .transfer {
                        transferSection
                    } else {
                        CategoryGrid(
                            categories: visibleCategories,
                            selection: model.category,
                            onSelect: { model.category = $0 },
                            onManage: { showCategories = true }
                        )
                    }
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.vertical, DS.Spacing.s)
                .id(model.kind)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .frame(maxHeight: .infinity)

            metaBar
                .padding(.vertical, DS.Spacing.s)

            if let error = model.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(DS.Colors.danger)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }

            CalculatorKeypad(
                commitTitle: model.isEditing ? "Update" : "Save",
                showsEquals: model.expression.hasPendingOperation,
                commitEnabled: model.canSave,
                tint: tint,
                onKey: handle
            )
            .padding(.horizontal, DS.Spacing.screen - 4)
            .padding(.bottom, DS.Spacing.s)
        }
        .sheet(isPresented: $showTags) {
            TagPickerSheet(selected: model.tags) { model.toggle($0) }
        }
        .sheet(isPresented: $showCategories) {
            NavigationStack {
                CategoryListView(initialKind: model.kind.categoryKind ?? .expense)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showCategories = false }
                        }
                    }
            }
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let entry = model.editing {
                    LedgerStore(context: context).delete(entry)
                    Haptics.success()
                    toasts.show(ToastMessage(symbol: "trash", text: String(localized: "Transaction deleted")))
                    dismiss()
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(DS.Colors.fill, in: Circle())
            }
            .accessibilityLabel(Text("Close"))

            Spacer()
            KindSwitcher(selection: model.kind) { model.setKind($0, categories: categories) }
            Spacer()

            if model.isEditing {
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Colors.danger)
                        .frame(width: 34, height: 34)
                        .background(DS.Colors.fill, in: Circle())
                }
                .accessibilityLabel(Text("Delete"))
            } else {
                Color.clear.frame(width: 34, height: 34)
            }
        }
    }

    // MARK: Amount

    private var amountDisplay: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(model.expression.hasPendingOperation ? model.expression.expressionText : " ")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Menu {
                    ForEach(accounts) { account in
                        Button {
                            model.selectAccount(account)
                        } label: {
                            Label(account.name + " · " + account.currencyCode, systemImage: account.symbolName)
                        }
                    }
                } label: {
                    Text(model.currencyCode)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.12), in: Capsule())
                }
                .accessibilityLabel(Text("Currency"))
                .accessibilityValue(Text(model.currencyCode))

                Spacer(minLength: 0)

                Text(MoneyFormat.string(model.amount, code: model.currencyCode))
                    .font(DS.Typography.entryAmount)
                    .monospacedDigit()
                    .foregroundStyle(model.amount < 0 ? DS.Colors.danger : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .contentTransition(.numericText(value: model.amount.doubleValue))
                    .animation(reduceMotion ? nil : DS.Motion.snappy, value: model.amount)
                    .modifier(ShakeEffect(shakes: CGFloat(shakeAmount)))
                    .accessibilityLabel(Text("Amount"))
                    .accessibilityValue(Text(MoneyFormat.string(model.amount, code: model.currencyCode)))
            }

            conversionHint
        }
    }

    @ViewBuilder
    private var conversionHint: some View {
        let base = AppSettings.baseCurrency
        if model.kind == .transfer, model.isCrossCurrencyTransfer, let dest = model.toAccount {
            let estimate = model.estimatedToAmount(converter: converter)
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                Text("Credited")
                TextField(
                    estimate.map { MoneyFormat.plain($0, fractionDigits: dest.currency.fractionDigits) } ?? "0",
                    text: $model.toAmountText
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .focused($focus, equals: .credited)
                Text(dest.currencyCode)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else if model.currencyCode != base, model.amount > 0,
                  let rate = converter.rate(from: model.currencyCode, to: base, on: model.date) {
            let converted = (model.amount * rate).rounded(scale: CurrencyInfo.info(for: base).fractionDigits)
            Text(verbatim: "≈ \(MoneyFormat.string(converted, code: base)) · 1 \(model.currencyCode) = \(MoneyFormat.rate(rate)) \(base)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: Note

    private var noteField: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.alignleft")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            TextField("Add a note", text: $model.note)
                .focused($focus, equals: .note)
                .submitLabel(.done)
                .onSubmit { focus = nil }
            if focus != nil {
                Button("Done") { focus = nil }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(DS.Colors.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
    }

    // MARK: Transfer

    private var transferSection: some View {
        TransferPanel(
            accounts: accounts,
            from: model.account,
            to: model.toAccount,
            onSelectFrom: { model.selectAccount($0) },
            onSelectTo: { model.toAccount = $0; model.toAmountText = "" },
            onSwap: { model.swapTransferAccounts() }
        )
        .padding(.top, 4)
    }

    // MARK: Meta

    private var metaBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if model.kind != .transfer {
                    Menu {
                        ForEach(accounts) { account in
                            Button {
                                model.selectAccount(account)
                            } label: {
                                Label(account.name + " · " + account.currencyCode, systemImage: account.symbolName)
                            }
                        }
                    } label: {
                        Chip(title: model.account?.name ?? String(localized: "Account"), symbol: model.account?.symbolName ?? "creditcard")
                    }
                }

                Button {
                    showDatePicker = true
                } label: {
                    Chip(title: dateLabel, symbol: "calendar", isSelected: !Calendar.current.isDateInToday(model.date), tint: tint)
                }
                .popover(isPresented: $showDatePicker) {
                    EntryDatePicker(date: $model.date)
                        .presentationCompactAdaptation(.popover)
                }

                Button {
                    showTags = true
                } label: {
                    Chip(
                        title: model.tags.isEmpty ? String(localized: "Tags") : model.tags.map(\.name).joined(separator: ", "),
                        symbol: "number",
                        isSelected: !model.tags.isEmpty,
                        tint: tint
                    )
                }
            }
            .padding(.horizontal, DS.Spacing.screen)
            .buttonStyle(PressableStyle(scale: 0.95))
        }
        .scrollIndicators(.hidden)
    }

    private var dateLabel: String {
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(model.date) { day = String(localized: "Today") }
        else if cal.isDateInYesterday(model.date) { day = String(localized: "Yesterday") }
        else { day = model.date.formatted(.dateTime.month(.abbreviated).day()) }
        return day + " " + model.date.timeText
    }

    // MARK: Keys

    private func handle(_ key: KeypadKey) {
        model.errorMessage = nil
        switch key {
        case .digit(let n): model.expression.input(digit: n)
        case .decimal: model.expression.inputDecimalPoint()
        case .op(let op): model.expression.input(op)
        case .backspace: model.expression.backspace()
        case .clear: model.expression.clear()
        case .commit:
            if model.expression.hasPendingOperation {
                model.expression.collapse()
            } else {
                commit()
            }
        }
    }

    private func commit() {
        guard model.canSave else {
            Haptics.error()
            withMotion(.linear(duration: 0.4)) { shakeAmount += 1 }
            if model.amount <= 0 { model.errorMessage = LedgerError.amountMustBePositive.localizedDescription }
            return
        }
        let wasEditing = model.isEditing
        guard let entry = model.save(context: context) else {
            Haptics.error()
            return
        }
        Haptics.success()
        let budgetNotice = BudgetNotifier.notice(after: entry, budgets: budgets, context: context)
        if let budgetNotice {
            toasts.show(budgetNotice, duration: .seconds(3.5))
        } else {
            let text = wasEditing ? String(localized: "Transaction updated") : String(localized: "Saved")
            toasts.show(ToastMessage(symbol: "checkmark.circle.fill", text: text, style: .success))
        }
        dismiss()
    }
}

/// Horizontal shake used to reject an invalid save.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 4), y: 0))
    }
}

/// Compact calendar + time picker with quick shortcuts.
struct EntryDatePicker: View {
    @Binding var date: Date

    var body: some View {
        VStack(spacing: DS.Spacing.m) {
            HStack(spacing: 8) {
                shortcut("Today", offset: 0)
                shortcut("Yesterday", offset: -1)
                shortcut("2 days ago", offset: -2)
            }
            DatePicker("Date", selection: $date, in: ...Date.distantFuture, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
            DatePicker("Time", selection: $date, displayedComponents: [.hourAndMinute])
        }
        .padding()
        .frame(minWidth: 320)
    }

    private func shortcut(_ title: LocalizedStringKey, offset: Int) -> some View {
        Button {
            Haptics.selection()
            let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
            date = day.combining(timeOf: date)
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DS.Colors.fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
