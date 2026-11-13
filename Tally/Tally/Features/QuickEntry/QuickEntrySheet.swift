import SwiftUI
import SwiftData

/// Bottom sheet for recording or editing an entry.
/// Common path: open → type amount → tap category → Save.
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
        .interactiveDismissDisabled(model?.hasChanges ?? false)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground {
            PageBackground()
        }
    }
}

private struct QuickEntryContent: View {
    @Bindable var model: QuickEntryViewModel
    var accounts: [Account]
    var categories: [LedgerCategory]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @Environment(LedgerCache.self) private var cache
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showDatePicker = false
    @State private var showTags = false
    @State private var showCategories = false
    @State private var showSplits = false
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    @State private var shakeAmount = 0
    @FocusState private var focus: Field?

    private enum Field { case note, payee, credited, fee, rate, discount }

    private var tint: Color {
        switch model.kind {
        case .expense: DS.Colors.accent
        case .income, .refund: DS.Colors.income
        case .transfer, .adjustment: DS.Colors.transfer
        }
    }

    private var visibleCategories: [LedgerCategory] {
        guard let kind = model.kind.categoryKind else { return [] }
        return categories.filter { $0.kind == kind && !$0.isArchived }
    }

    private var base: String { AppSettings.baseCurrency }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, 18)

            amountDisplay
                .padding(.horizontal, DS.Spacing.screen + 4)
                .padding(.top, DS.Spacing.m)

            textFields
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, DS.Spacing.s)

            if model.kind == .expense {
                priceAdjustmentFields
                    .padding(.horizontal, DS.Spacing.screen)
                    .padding(.top, DS.Spacing.s)
                    .transition(.opacity)
            }

            ScrollView {
                Group {
                    if model.kind == .transfer {
                        transferSection
                    } else if !model.splits.isEmpty {
                        splitSummary
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
                .transition(.opacity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .frame(maxHeight: .infinity)

            metaBar.padding(.vertical, DS.Spacing.s)

            if let error = model.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(DS.Colors.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
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
        .sheet(isPresented: $showSplits) {
            SplitEditorSheet(total: model.amount, currency: model.currencyCode, categories: visibleCategories, splits: $model.splits) { newTotal in
                model.setAmount(newTotal)
            }
        }
        .sheet(isPresented: $showCategories) {
            NavigationStack {
                CategoryListView(initialKind: model.kind.categoryKind ?? .expense)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showCategories = false } }
                    }
            }
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let entry = model.editing {
                    try? TransactionService(context: context).delete(entry)
                    Haptics.success()
                    toasts.show(ToastMessage(symbol: "trash", text: String(localized: "Transaction deleted")))
                    dismiss()
                }
            }
        }
        .confirmationDialog("Discard this entry?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button {
                if model.hasChanges { confirmDiscard = true } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(DS.Colors.fill, in: Circle())
            }
            .accessibilityLabel(Text("Cancel"))

            Spacer()
            if model.isRefund {
                Label(TransactionKind.refund.title, systemImage: TransactionKind.refund.symbol)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(DS.Colors.fill, in: Capsule())
            } else {
                KindSwitcher(selection: model.kind) { model.setKind($0, categories: categories) }
            }
            Spacer()

            if model.isEditing {
                Button { confirmDelete = true } label: {
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
            if let original = model.refundOf {
                Text("Refund of \(original.displayTitle) · \(original.date.shortDateText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(model.expression.hasPendingOperation ? model.expression.expressionText : " ")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Menu {
                    ForEach(accounts) { account in
                        Button { model.selectAccount(account) } label: {
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

                Text(MoneyFormat.string(model.amount, code: model.currencyCode, reveal: true))
                    .font(DS.Typography.entryAmount)
                    .monospacedDigit()
                    .foregroundStyle(model.amount < 0 ? DS.Colors.danger : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .contentTransition(.numericText(value: model.amount.doubleValue))
                    .animation(reduceMotion ? nil : DS.Motion.snappy, value: model.amount)
                    .modifier(ShakeEffect(shakes: CGFloat(shakeAmount)))
                    .accessibilityLabel(Text("Amount"))
                    .accessibilityValue(Text(MoneyFormat.string(model.amount, code: model.currencyCode, reveal: true)))
            }

            conversionRow

            if model.hasPriceAdjustments {
                paidRow
            }
        }
    }

    /// "Paid ¥77.00 = 85.00 − 10.00 + 2.00" for expenses with a discount or fee.
    private var paidRow: some View {
        HStack(spacing: 6) {
            if model.discount > model.amount {
                Text("The discount can't be negative or more than the amount.")
                    .foregroundStyle(DS.Colors.danger)
            } else {
                Text("Paid")
                Text(MoneyFormat.string(model.paidAmount, code: model.currencyCode, reveal: true))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(value: model.paidAmount.doubleValue))
            }
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }

    // MARK: Discount and fee

    private var priceAdjustmentFields: some View {
        HStack(spacing: DS.Spacing.s) {
            adjustmentField(title: "Discount", symbol: "tag", text: $model.discountText, field: .discount)
            adjustmentField(title: "Fee", symbol: "percent", text: $model.feeText, field: .fee)
        }
    }

    private func adjustmentField(title: LocalizedStringKey, symbol: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).font(.subheadline)
            Text(title).foregroundStyle(.secondary).font(.subheadline)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focus, equals: field)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(DS.Colors.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
    }

    /// Exchange-rate line for foreign-currency entries; the rate can be typed in.
    @ViewBuilder
    private var conversionRow: some View {
        if model.kind != .transfer, model.currencyCode != base {
            let stored = cache.converter.rate(from: model.currencyCode, to: base, on: model.date)
            HStack(spacing: 6) {
                Text(verbatim: "1 \(model.currencyCode) =")
                TextField(stored.map { MoneyFormat.rate($0) } ?? String(localized: "rate"), text: $model.manualRateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    .focused($focus, equals: .rate)
                Text(verbatim: base)
                Spacer()
                if let rate = model.manualRate ?? stored, model.amount > 0 {
                    Text(verbatim: "≈ " + MoneyFormat.string((model.amount * rate).rounded(scale: CurrencyInfo.info(for: base).fractionDigits), code: base, reveal: true))
                } else if model.manualRate == nil && stored == nil {
                    Text("Pending conversion").foregroundStyle(DS.Colors.warning)
                }
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Text fields

    private var textFields: some View {
        HStack(spacing: DS.Spacing.s) {
            HStack(spacing: 8) {
                Image(systemName: "storefront").foregroundStyle(.secondary).font(.subheadline)
                TextField("Payee", text: $model.payee)
                    .focused($focus, equals: .payee)
                    .submitLabel(.next)
                    .onSubmit { focus = .note }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(DS.Colors.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
            .frame(maxWidth: 150)

            HStack(spacing: 8) {
                Image(systemName: "text.alignleft").foregroundStyle(.secondary).font(.subheadline)
                TextField("Add a note", text: $model.note)
                    .focused($focus, equals: .note)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
                if focus != nil {
                    Button("Done") { focus = nil }.font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(DS.Colors.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        }
    }

    // MARK: Transfer

    private var transferSection: some View {
        VStack(spacing: DS.Spacing.m) {
            TransferPanel(
                accounts: accounts,
                from: model.account,
                to: model.toAccount,
                onSelectFrom: { model.selectAccount($0) },
                onSelectTo: { model.toAccount = $0; model.toAmountText = "" },
                onSwap: { model.swapTransferAccounts() }
            )
            VStack(spacing: 0) {
                if model.isCrossCurrencyTransfer, let dest = model.toAccount {
                    let estimate = model.estimatedToAmount(converter: cache.converter)
                    fieldRow(title: "Received", symbol: "arrow.down.to.line") {
                        TextField(estimate.map { MoneyFormat.plain($0, fractionDigits: dest.currency.fractionDigits) } ?? String(localized: "Required"),
                                  text: $model.toAmountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .credited)
                        Text(dest.currencyCode).foregroundStyle(.secondary)
                    }
                    Divider().padding(.leading, 44)
                }
                fieldRow(title: "Fee", symbol: "percent") {
                    TextField("0", text: $model.feeText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focus, equals: .fee)
                    Text(model.currencyCode).foregroundStyle(.secondary)
                }
            }
            .background(DS.Colors.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
            if model.toAccount?.kind.isLiability == true {
                Text("Repayment: lowers the amount owed. It is not counted as spending again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.fee > 0 {
                Text("The fee is recorded as spending in the Fees category.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 4)
    }

    private func fieldRow<Content: View>(title: LocalizedStringKey, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: DS.Spacing.m) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
            Text(title)
            Spacer()
            content()
        }
        .font(.subheadline)
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, 11)
    }

    // MARK: Splits

    private var splitSummary: some View {
        Button { showSplits = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Split into \(model.splits.count)", systemImage: "square.split.2x2")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Edit").font(.subheadline)
                }
                ForEach(model.splits) { s in
                    HStack {
                        SymbolBadge(symbol: s.category?.symbolName ?? "questionmark", colorHex: s.category?.colorHex ?? "8E8E93", size: 26)
                        Text(s.category?.name ?? String(localized: "Choose category"))
                        Spacer()
                        Text(MoneyFormat.string(s.amount, code: model.currencyCode, reveal: true)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
                if !model.splitTotal.isSameAmount(as: model.amount) {
                    Text("Splits total \(MoneyFormat.string(model.splitTotal, code: model.currencyCode, reveal: true)) — must equal the amount.")
                        .font(.footnote)
                        .foregroundStyle(DS.Colors.warning)
                }
            }
            .padding(DS.Spacing.m)
            .background(DS.Colors.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Meta

    private var metaBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if model.kind != .transfer {
                    Menu {
                        ForEach(accounts) { account in
                            Button { model.selectAccount(account) } label: {
                                Label(account.name + " · " + account.currencyCode, systemImage: account.symbolName)
                            }
                        }
                    } label: {
                        Chip(title: model.account?.name ?? String(localized: "Account"), symbol: model.account?.symbolName ?? "creditcard")
                    }
                }

                Button { showDatePicker = true } label: {
                    Chip(title: dateLabel, symbol: "calendar", isSelected: !Calendar.current.isDateInToday(model.date), tint: tint)
                }
                .popover(isPresented: $showDatePicker) {
                    EntryDatePicker(date: $model.date)
                        .presentationCompactAdaptation(.popover)
                }

                if model.kind == .expense {
                    Button {
                        if model.splits.isEmpty, model.amount > 0 {
                            model.splits = [SplitDraft(category: model.category, amount: model.amount)]
                        }
                        showSplits = true
                    } label: {
                        Chip(title: String(localized: "Split"), symbol: "square.split.2x2", isSelected: !model.splits.isEmpty, tint: tint)
                    }
                    .disabled(model.amount <= 0)
                }

                Button { showTags = true } label: {
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
        else { day = model.date.text(.dateTime.month(.abbreviated).day()) }
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
            if model.amount <= 0 {
                model.errorMessage = LedgerError.amountMustBePositive.localizedDescription
            } else if !model.splits.isEmpty && !model.splitTotal.isSameAmount(as: model.amount) {
                model.errorMessage = LedgerError.splitTotalMismatch.localizedDescription
            }
            return
        }
        let wasEditing = model.isEditing
        // The entry is shown only after it has been written successfully.
        guard let entry = model.save(context: context) else {
            Haptics.error()
            return
        }
        Haptics.success()
        if let notice = BudgetNotifier.notice(after: entry, context: context) {
            toasts.show(notice, duration: .seconds(3.5))
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
            DatePicker("Date", selection: $date, displayedComponents: [.date])
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

/// Edit how one expense is divided between categories.
struct SplitEditorSheet: View {
    let total: Decimal
    let currency: String
    let categories: [LedgerCategory]
    @Binding var splits: [SplitDraft]
    /// Replaces the entry's total (offered when the parts add up to something else).
    var onChangeTotal: (Decimal) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []
    /// The first row absorbs whatever is left until the user edits it directly.
    @State private var balancingRowID: UUID?
    @State private var confirmMismatch = false
    @FocusState private var focusedRow: UUID?

    struct Row: Identifiable {
        let id = UUID()
        var category: LedgerCategory?
        var amountText: String
    }

    private var digits: Int { CurrencyInfo.info(for: currency).fractionDigits }
    private func amount(_ row: Row) -> Decimal { (DecimalCodec.parseLenient(row.amountText) ?? 0).rounded(scale: digits) }
    private var allocated: Decimal { rows.sum { amount($0) } }
    private var remaining: Decimal { (total - allocated).rounded(scale: digits) }

    /// Why Done can't finish yet, if anything is missing (a mismatch is handled on Done).
    private var problem: String? {
        if rows.count < 2 { return String(localized: "Add at least two parts.") }
        if !rows.allSatisfy({ $0.category != nil && amount($0) > 0 }) {
            return String(localized: "Each part needs a category and an amount.")
        }
        return nil
    }

    /// Row that can take the difference: the one with the largest amount that stays above zero.
    private var adjustableRow: Row? {
        rows.filter { amount($0) + remaining > 0 }.max { amount($0) < amount($1) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Total", value: MoneyFormat.string(total, code: currency, reveal: true))
                    LabeledContent("Remaining", value: MoneyFormat.string(remaining, code: currency, reveal: true))
                        .foregroundStyle(remaining.isZero ? Color.secondary : DS.Colors.warning)
                }
                Section {
                    ForEach($rows) { $row in
                        HStack {
                            Menu {
                                ForEach(categories) { c in
                                    Button { row.category = c } label: { Label(c.name, systemImage: c.symbolName) }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    SymbolBadge(symbol: row.category?.symbolName ?? "questionmark", colorHex: row.category?.colorHex ?? "8E8E93", size: 28)
                                    Text(row.category?.name ?? String(localized: "Choose category"))
                                        .foregroundStyle(row.category == nil ? Color.secondary : Color.primary)
                                }
                            }
                            Spacer()
                            TextField("0", text: $row.amountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(maxWidth: 110)
                                .focused($focusedRow, equals: row.id)
                        }
                    }
                    .onDelete { offsets in
                        rows.remove(atOffsets: offsets)
                        if let id = balancingRowID, !rows.contains(where: { $0.id == id }) { balancingRowID = nil }
                        rebalance()
                    }
                    Button {
                        rows.append(Row(category: nil, amountText: remaining > 0 ? DecimalCodec.encode(remaining) : ""))
                    } label: {
                        Label("Add Split", systemImage: "plus.circle.fill")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let problem {
                            Text(problem).foregroundStyle(DS.Colors.warning)
                        }
                        if balancingRowID != nil {
                            Text("The first part fills in the rest automatically until you edit it.")
                        }
                        Text("Each part is counted in its own category for reports and budgets. The account balance changes once, by the total.")
                    }
                }
                if !splits.isEmpty {
                    Section {
                        Button("Remove Split", role: .destructive) {
                            splits = []
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Split")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        focusedRow = nil
                        if remaining.isZero {
                            finish()
                        } else {
                            Haptics.warning()
                            confirmMismatch = true
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(problem != nil)
                }
            }
            .confirmationDialog(
                Text("Parts add up to \(MoneyFormat.string(allocated, code: currency, reveal: true)), but the total is \(MoneyFormat.string(total, code: currency, reveal: true))."),
                isPresented: $confirmMismatch,
                titleVisibility: .visible
            ) {
                Button("Change total to \(MoneyFormat.string(allocated, code: currency, reveal: true))") {
                    onChangeTotal(allocated)
                    finish()
                }
                if let row = adjustableRow {
                    let adjusted = (amount(row) + remaining).rounded(scale: digits)
                    let name = row.category?.name ?? String(localized: "Uncategorized")
                    let value = MoneyFormat.string(adjusted, code: currency, reveal: true)
                    Button("Set \(name) to \(value)") {
                        if let i = rows.firstIndex(where: { $0.id == row.id }) {
                            rows[i].amountText = DecimalCodec.encode(adjusted)
                        }
                        finish()
                    }
                }
                Button("Keep Editing", role: .cancel) {}
            }
            .onChange(of: rows.map(\.amountText)) { _, _ in rebalance() }
            .onChange(of: focusedRow) { _, row in
                // Typing into the balancing row hands it over to the user.
                if let row, row == balancingRowID { balancingRowID = nil }
            }
        }
        .onAppear {
            rows = splits.map { Row(category: $0.category, amountText: DecimalCodec.encode($0.amount)) }
            if rows.isEmpty {
                let first = Row(category: nil, amountText: DecimalCodec.encode(total))
                rows = [first, Row(category: nil, amountText: "")]
                balancingRowID = first.id
            } else if rows.count < 2 {
                rows.append(Row(category: nil, amountText: remaining > 0 ? DecimalCodec.encode(remaining) : ""))
            }
        }
    }

    /// Keeps the balancing row equal to total minus the other parts (never below zero).
    private func rebalance() {
        guard let id = balancingRowID, let i = rows.firstIndex(where: { $0.id == id }) else { return }
        let others = rows.filter { $0.id != id }.sum { amount($0) }
        let value = max(0, (total - others).rounded(scale: digits))
        let text = value > 0 ? DecimalCodec.encode(value) : ""
        if rows[i].amountText != text { rows[i].amountText = text }
    }

    private func finish() {
        splits = rows.map { SplitDraft(category: $0.category, amount: amount($0)) }
        dismiss()
    }
}
