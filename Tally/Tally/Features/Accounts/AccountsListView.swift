import SwiftUI
import SwiftData

struct AccountsListView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID: String = ""
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var entries: [LedgerEntry]
    @Query private var rates: [ExchangeRate]

    @State private var editor: AccountEditorRequest?
    @State private var pendingDelete: Account?

    var body: some View {
        let math = LedgerMath(base: baseCurrency, rates: rates)
        let balances = math.balances(accounts: accounts, entries: entries)
        let worth = math.netWorth(accounts: accounts, balances: balances)
        let active = accounts.filter { !$0.isArchived }
        let archived = accounts.filter(\.isArchived)

        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Net worth").font(.subheadline).foregroundStyle(.secondary)
                    AmountText(value: worth.net, code: baseCurrency, font: DS.Typography.heroAmount)
                    HStack(spacing: DS.Spacing.l) {
                        Text("Assets \(MoneyFormat.string(worth.assets, code: baseCurrency))")
                        Text("Liabilities \(MoneyFormat.string(worth.liabilities, code: baseCurrency))")
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section {
                ForEach(active) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        AccountRow(account: account, balance: balances[account.id] ?? 0, base: baseCurrency, math: math,
                                   isDefault: defaultAccountID == account.id.uuidString)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { pendingDelete = account } label: { Label("Delete", systemImage: "trash") }
                        Button { setArchived(account, true) } label: { Label("Archive", systemImage: "archivebox") }
                            .tint(.gray)
                    }
                    .swipeActions(edge: .leading) {
                        Button { editor = AccountEditorRequest(account: account) } label: { Label("Edit", systemImage: "pencil") }
                            .tint(DS.Colors.accent)
                    }
                }
                .onMove(perform: move)
            } header: {
                Text("Accounts")
            } footer: {
                Text("Balances are calculated from each account's opening balance and every recorded transaction.")
            }

            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { account in
                        NavigationLink {
                            AccountDetailView(account: account)
                        } label: {
                            AccountRow(account: account, balance: balances[account.id] ?? 0, base: baseCurrency, math: math, isDefault: false)
                                .opacity(0.6)
                        }
                        .swipeActions {
                            Button { setArchived(account, false) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                                .tint(DS.Colors.accent)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = AccountEditorRequest(account: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Add Account"))
            }
        }
        .sheet(item: $editor) { request in
            AccountEditorSheet(account: request.account)
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { account in
            Button("Delete Account and \(account.entryCount) Transactions", role: .destructive) {
                withMotion { LedgerStore(context: context).deleteAccount(account) }
                Haptics.success()
            }
            Button("Archive Instead") { setArchived(account, true) }
        } message: { _ in
            Text("Deleting removes every transaction that uses this account. Archiving hides it but keeps history.")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var active = accounts.filter { !$0.isArchived }
        active.move(fromOffsets: source, toOffset: destination)
        for (index, account) in active.enumerated() { account.sortOrder = index }
        try? context.save()
    }

    private func setArchived(_ account: Account, _ archived: Bool) {
        withMotion { account.isArchived = archived }
        try? context.save()
        Haptics.selection()
    }
}

struct AccountEditorRequest: Identifiable {
    let id = UUID()
    var account: Account?
}

struct AccountRow: View {
    let account: Account
    let balance: Decimal
    let base: String
    let math: LedgerMath
    var isDefault: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            SymbolBadge(symbol: account.symbolName, colorHex: account.colorHex, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name).font(.body.weight(.medium))
                    if isDefault {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Colors.accent.opacity(0.12), in: Capsule())
                            .foregroundStyle(DS.Colors.accent)
                    }
                }
                Text(verbatim: account.kind.title + " · " + account.currencyCode)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(MoneyFormat.string(balance, code: account.currencyCode))
                    .font(DS.Typography.rowAmount)
                    .monospacedDigit()
                    .foregroundStyle(balance < 0 ? DS.Colors.danger : Color.primary)
                if account.currencyCode != base {
                    Text(verbatim: "≈ " + MoneyFormat.string(math.converter.convertOrSame(balance, from: account.currencyCode, to: base), code: base))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
