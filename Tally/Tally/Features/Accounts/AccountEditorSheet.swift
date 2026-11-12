import SwiftUI
import SwiftData

struct AccountEditorSheet: View {
    let account: Account?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID: String = ""

    @State private var name = ""
    @State private var kind: AccountKind = .debitCard
    @State private var currencyCode = "CNY"
    @State private var openingText = ""
    @State private var colorHex = "3E7BFA"
    @State private var symbol = "creditcard"
    @State private var includeInTotal = true
    @State private var isDefault = false
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var symbolTouched = false

    private var hasEntries: Bool { (account?.entryCount ?? 0) > 0 }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

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

                Section("Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(AccountKind.allCases) { k in
                            Label(k.title, systemImage: k.defaultSymbol).tag(k)
                        }
                    }
                    .onChange(of: kind) { _, newKind in
                        if !symbolTouched { symbol = newKind.defaultSymbol }
                    }
                }

                Section {
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(CurrencyInfo.all) { c in
                            Text(verbatim: "\(c.code) · \(c.localizedName)").tag(c.code)
                        }
                    }
                    .disabled(hasEntries)
                    HStack {
                        Text("Opening balance")
                        Spacer()
                        TextField("0", text: $openingText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if hasEntries {
                            Text("The currency can't change once transactions exist, so past amounts stay correct.")
                        }
                        if kind.isLiability {
                            Text("For credit cards, enter the amount owed as a negative number, e.g. -1200.")
                        }
                    }
                }

                Section("Color") {
                    ColorSwatchPicker(selection: $colorHex)
                }

                Section("Icon") {
                    SymbolPickerGrid(symbols: SymbolLibrary.accounts, selection: Binding(
                        get: { symbol },
                        set: { symbol = $0; symbolTouched = true }
                    ), colorHex: colorHex)
                }

                Section {
                    Toggle("Include in total assets", isOn: $includeInTotal)
                    Toggle("Default account for new entries", isOn: $isDefault)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let account {
                        dismiss()
                        let store = LedgerStore(context: context)
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            store.deleteAccount(account)
                            Haptics.success()
                        }
                    }
                }
            } message: {
                Text("This also deletes \(account?.entryCount ?? 0) transactions that use this account.")
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let account {
            name = account.name
            kind = account.kind
            currencyCode = account.currencyCode
            openingText = account.openingBalance == 0 ? "" : DecimalCodec.encode(account.openingBalance)
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
        let opening = DecimalCodec.parseLenient(openingText) ?? 0
        let target: Account
        if let account {
            target = account
        } else {
            target = Account(name: trimmed, kind: kind, currencyCode: currencyCode, sortOrder: LedgerStore(context: context).nextAccountSortOrder())
            context.insert(target)
        }
        target.name = trimmed
        target.kind = kind
        if !hasEntries { target.currencyCode = currencyCode }
        target.openingBalance = opening.rounded(scale: CurrencyInfo.info(for: target.currencyCode).fractionDigits)
        target.colorHex = colorHex
        target.symbolName = symbol
        target.includeInTotal = includeInTotal
        try? context.save()

        if isDefault {
            defaultAccountID = target.id.uuidString
        } else if defaultAccountID == target.id.uuidString {
            defaultAccountID = ""
        }
        Haptics.success()
        dismiss()
    }
}
