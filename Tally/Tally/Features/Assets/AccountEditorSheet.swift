import SwiftUI
import SwiftData

struct AccountEditorSheet: View {
    let account: Account?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID: String = ""
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]

    @State private var name = ""
    @State private var kind: AccountKind = .debitCard
    @State private var currencyCode = "CNY"
    @State private var openingText = ""
    @State private var openingDate = Date.now
    @State private var openingDateTouched = false
    @State private var group = ""
    @State private var note = ""
    @State private var colorHex = "3E7BFA"
    @State private var symbol = "creditcard"
    @State private var includeInTotal = true
    @State private var isDefault = false
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var symbolTouched = false
    @State private var error: String?

    private var hasEntries: Bool { (account?.entryCount ?? 0) > 0 }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var existingGroups: [String] {
        Array(Set(allAccounts.map(\.groupName).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: DS.Spacing.m) {
                        SymbolBadge(symbol: symbol, colorHex: colorHex, size: 44, style: .solid)
                        TextField("Account name", text: $name)
                            .font(.title3.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(AccountKind.allCases) { k in
                            Label(k.title, systemImage: k.defaultSymbol).tag(k)
                        }
                    }
                    .onChange(of: kind) { _, newKind in
                        if !symbolTouched { symbol = newKind.defaultSymbol }
                    }
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(CurrencyInfo.all) { c in
                            Text(verbatim: "\(c.code) · \(c.localizedName)").tag(c.code)
                        }
                    }
                    .disabled(hasEntries)
                } footer: {
                    if hasEntries {
                        Text("The currency can't change once transactions exist, so past amounts stay correct.")
                    }
                }

                Section {
                    HStack {
                        Text(kind.isLiability ? String(localized: "Amount owed") : String(localized: "Opening balance"))
                        Spacer()
                        TextField("0", text: $openingText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    DatePicker("Balance as of", selection: Binding(
                        get: { openingDate },
                        set: { openingDate = $0; openingDateTouched = true }
                    ), displayedComponents: .date)
                } header: {
                    Text("Opening Balance")
                } footer: {
                    Text("The balance at the start of this day. Transactions dated earlier still appear in reports but don't change the balance.")
                }

                Section("Group") {
                    TextField("Group name (optional)", text: $group)
                    if !existingGroups.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(existingGroups, id: \.self) { g in
                                    Button { group = g } label: { Chip(title: g, isSelected: g == group) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                Section("Color") { ColorSwatchPicker(selection: $colorHex) }

                Section("Icon") {
                    SymbolPickerGrid(symbols: SymbolLibrary.accounts, selection: Binding(
                        get: { symbol },
                        set: { symbol = $0; symbolTouched = true }
                    ), colorHex: colorHex)
                }

                Section {
                    Toggle("Include in net worth", isOn: $includeInTotal)
                    Toggle("Default account for new entries", isOn: $isDefault)
                    TextField("Note", text: $note, axis: .vertical)
                }

                if let error {
                    Section { Text(error).foregroundStyle(DS.Colors.danger) }
                }

                if let account {
                    Section {
                        Button(account.isArchived ? String(localized: "Restore Account") : String(localized: "Archive Account")) {
                            account.isArchived.toggle()
                            try? context.save()
                            Haptics.selection()
                            dismiss()
                        }
                        Button("Delete Account", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Archived accounts are hidden from pickers but keep their history and balance.")
                    }
                }
            }
            .navigationTitle(account == nil ? String(localized: "New Account") : String(localized: "Edit Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).disabled(!canSave)
                }
            }
            .confirmationDialog("Delete account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let account else { return }
                    let repository = LedgerRepository(context: context)
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        try? repository.deleteAccount(account)
                        Haptics.success()
                    }
                }
            } message: {
                Text("This also deletes \(account?.entryCount ?? 0) transactions that use this account. Archiving keeps them.")
            }
        }
        .interactiveDismissDisabled(account == nil && !name.isEmpty)
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let account {
            name = account.name
            kind = account.kind
            currencyCode = account.currencyCode
            let opening = account.kind.isLiability ? -account.openingBalance : account.openingBalance
            openingText = opening == 0 ? "" : DecimalCodec.encode(opening)
            openingDate = account.openingDate > Date.distantPast.addingTimeInterval(86_400) ? account.openingDate : account.createdAt
            group = account.groupName
            note = account.note
            colorHex = account.colorHex
            symbol = account.symbolName
            symbolTouched = true
            includeInTotal = account.includeInTotal
            isDefault = defaultAccountID == account.id.uuidString
        } else {
            currencyCode = baseCurrency
            colorHex = DS.Palette.swatches.randomElement() ?? "3E7BFA"
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let typed = DecimalCodec.parseLenient(openingText) ?? 0
        let opening = kind.isLiability ? -typed.magnitudeValue : typed
        let repository = LedgerRepository(context: context)
        let target: Account
        if let account {
            target = account
        } else {
            target = Account(name: trimmed, kind: kind, currencyCode: currencyCode, sortOrder: repository.nextAccountSortOrder())
            context.insert(target)
        }
        target.name = trimmed
        target.kind = kind
        if !hasEntries { target.currencyCode = currencyCode }
        target.openingBalance = opening.rounded(scale: CurrencyInfo.info(for: target.currencyCode).fractionDigits)
        // Accounts created before opening dates existed count every transaction;
        // keep that unless the user picks a date explicitly.
        let legacy = account.map { $0.openingDate <= Date.distantPast.addingTimeInterval(86_400) } ?? false
        if !legacy || openingDateTouched {
            target.openingDate = Calendar.ledger.startOfDay(for: openingDate)
        }
        target.groupName = group.trimmingCharacters(in: .whitespacesAndNewlines)
        target.note = note
        target.colorHex = colorHex
        target.symbolName = symbol
        target.includeInTotal = includeInTotal
        do {
            try repository.commit()
        } catch {
            self.error = error.localizedDescription
            return
        }
        if isDefault {
            defaultAccountID = target.id.uuidString
        } else if defaultAccountID == target.id.uuidString {
            defaultAccountID = ""
        }
        Haptics.success()
        dismiss()
    }
}
