import SwiftUI
import SwiftData

/// Default tab: where the money is. Net worth, assets, liabilities and accounts —
/// no income/expense or budget information (those live in their own tabs).
struct AssetsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LedgerCache.self) private var cache
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @AppStorage(SettingsKey.hideAmounts) private var hideAmounts = false
    @AppStorage(SettingsKey.accountGrouping) private var groupingRaw: String = AccountGrouping.type.rawValue
    @AppStorage("assets.showArchived") private var showArchived = false

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @State private var editor: AccountEditorRequest?
    @State private var confirmClearDemo = false
    @State private var showRates = false

    private var grouping: AccountGrouping { AccountGrouping(rawValue: groupingRaw) ?? .type }

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    struct AccountSection: Identifiable {
        let id: String
        let accounts: [Account]
    }

    /// Sections in display order.
    private var sections: [AccountSection] {
        let list = activeAccounts
        switch grouping {
        case .type:
            let kinds = AccountKind.allCases.filter { k in list.contains { $0.kind == k } }
            return kinds.map { k in AccountSection(id: k.title, accounts: list.filter { $0.kind == k }) }
        case .currency:
            let codes = Array(Set(list.map(\.currencyCode))).sorted { a, b in
                a == baseCurrency ? true : (b == baseCurrency ? false : a < b)
            }
            return codes.map { c in
                AccountSection(id: c + " · " + CurrencyInfo.info(for: c).localizedName, accounts: list.filter { $0.currencyCode == c })
            }
        case .custom:
            let names = Array(Set(list.map(\.groupName))).sorted { a, b in
                a.isEmpty ? false : (b.isEmpty ? true : a.localizedCompare(b) == .orderedAscending)
            }
            return names.map { n in
                AccountSection(id: n.isEmpty ? String(localized: "Ungrouped") : n, accounts: list.filter { $0.groupName == n })
            }
        }
    }

    var body: some View {
        let worth = cache.netWorth(base: baseCurrency)
        NavigationStack {
            List {
                Section {
                    NetWorthHeader(worth: worth, base: baseCurrency, accounts: accounts, onChangeBase: changeBase) {
                        showRates = true
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))

                if accounts.contains(where: \.isDemo) {
                    Section {
                        DemoNotice { confirmClearDemo = true }
                    }
                }

                if activeAccounts.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No Accounts", systemImage: "wallet.pass")
                        } description: {
                            Text("Add cash, cards, savings or debts to see where your money is.")
                        } actions: {
                            Button("Add Account") { editor = AccountEditorRequest(account: nil) }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule)
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(sections) { section in
                    Section {
                        ForEach(section.accounts) { account in
                            NavigationLink(value: account) {
                                AccountRow(account: account, balance: cache.balance(of: account.id), base: baseCurrency,
                                           converter: cache.converter)
                            }
                            .swipeActions(edge: .trailing) {
                                Button { setArchived(account, true) } label: { Label("Archive", systemImage: "archivebox") }
                                    .tint(.gray)
                                Button { editor = AccountEditorRequest(account: account) } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(DS.Colors.accent)
                            }
                        }
                        .onMove { move(section.accounts, from: $0, to: $1) }
                    } header: {
                        SectionTotal(title: section.id, accounts: section.accounts, base: baseCurrency, cache: cache)
                    }
                }

                if showArchived {
                    let archived = accounts.filter(\.isArchived)
                    if !archived.isEmpty {
                        Section("Archived") {
                            ForEach(archived) { account in
                                NavigationLink(value: account) {
                                    AccountRow(account: account, balance: cache.balance(of: account.id), base: baseCurrency,
                                               converter: cache.converter)
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
            }
            .listStyle(.insetGrouped)
            .pageBackground()
            .navigationTitle("Assets")
            .toolbar { toolbar }
            .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
            .navigationDestination(for: LedgerEntry.self) { TransactionDetailView(entry: $0) }
            .navigationDestination(isPresented: $showRates) { ExchangeRatesView() }
            .sheet(item: $editor) { request in
                AccountEditorSheet(account: request.account)
            }
            .confirmationDialog("Remove demo data?", isPresented: $confirmClearDemo, titleVisibility: .visible) {
                Button("Remove Demo Data", role: .destructive) {
                    try? LedgerRepository(context: context).deleteDemoData()
                    Haptics.success()
                }
            } message: {
                Text("Demo accounts, their transactions, demo tags, budgets, plans and rates will be deleted. Your own records are kept.")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Haptics.selection()
                hideAmounts.toggle()
            } label: {
                Image(systemName: hideAmounts ? "eye.slash" : "eye")
            }
            .accessibilityLabel(hideAmounts ? Text("Show Amounts") : Text("Hide Amounts"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Group", selection: $groupingRaw) {
                    ForEach(AccountGrouping.allCases) { g in Text(g.title).tag(g.rawValue) }
                }
                Toggle("Show Archived", isOn: $showArchived)
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel(Text("View Options"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            AddMenuButton {
                Button { editor = AccountEditorRequest(account: nil) } label: { Label("New Account", systemImage: "wallet.pass") }
            }
        }
    }

    private func changeBase(_ code: String) {
        guard code != baseCurrency else { return }
        baseCurrency = code
        cache.reload()
        Haptics.selection()
    }

    private func move(_ list: [Account], from source: IndexSet, to destination: Int) {
        var reordered = list
        reordered.move(fromOffsets: source, toOffset: destination)
        // Keep the section's existing sort slots, assign them in the new order.
        let slots = list.map(\.sortOrder).sorted()
        for (account, slot) in zip(reordered, slots) { account.sortOrder = slot }
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

// MARK: - Header

private struct NetWorthHeader: View {
    let worth: NetWorth
    let base: String
    let accounts: [Account]
    var onChangeBase: (String) -> Void
    var onShowRates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("Net Worth")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(CurrencyInfo.all) { c in
                        Button { onChangeBase(c.code) } label: {
                            if c.code == base {
                                Label(c.code + " · " + c.localizedName, systemImage: "checkmark")
                            } else {
                                Text(verbatim: c.code + " · " + c.localizedName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(base)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DS.Colors.fill, in: Capsule())
                }
                .accessibilityLabel(Text("Base Currency"))
                .accessibilityValue(Text(base))
            }

            AmountText(value: worth.net, code: base, font: DS.Typography.heroAmount,
                       color: worth.net < 0 ? DS.Colors.danger : .primary)

            HStack(alignment: .top, spacing: DS.Spacing.xl) {
                MetricView(title: "Total Assets", value: worth.assets, code: base)
                Rectangle().fill(DS.Colors.separator.opacity(0.5)).frame(width: 0.5, height: 34)
                MetricView(title: "Total Liabilities", value: worth.liabilities, code: base,
                           color: worth.liabilities > 0 ? DS.Colors.danger : .primary)
                Spacer(minLength: 0)
            }

            if !worth.pendingAccountIDs.isEmpty {
                let names = accounts.filter { worth.pendingAccountIDs.contains($0.id) }.map(\.name).joined(separator: ", ")
                Button(action: onShowRates) {
                    Label {
                        Text("Pending conversion: \(names). Add an exchange rate to include them.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.footnote)
                    .foregroundStyle(DS.Colors.warning)
                    .multilineTextAlignment(.leading)
                }
                .buttonStyle(.borderless)
            }
        }
        .card(padding: DS.Spacing.xl)
    }
}

private struct DemoNotice: View {
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            Image(systemName: "sparkles").foregroundStyle(DS.Colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Demo data").font(.subheadline.weight(.semibold))
                Text("Sample records for exploring Tally.").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove", action: onClear)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        }
    }
}

/// Section header with the section's converted total.
private struct SectionTotal: View {
    let title: String
    let accounts: [Account]
    let base: String
    let cache: LedgerCache

    var body: some View {
        let engine = cache.engine(base: base)
        let values = accounts.filter(\.includeInTotal).map { a in
            engine.converter.convert(cache.balance(of: a.id), from: a.currencyCode, to: base)
        }
        let total = values.compactMap { $0 }.sum { $0 }
        HStack {
            Text(title)
            Spacer()
            if !values.isEmpty {
                Text(MoneyFormat.string(total, code: base) + (values.contains(where: { $0 == nil }) ? " *" : ""))
                    .monospacedDigit()
            }
        }
        .font(.footnote.weight(.medium))
        .textCase(nil)
    }
}

// MARK: - Shared rows and buttons

struct AccountRow: View {
    let account: Account
    let balance: Decimal
    let base: String
    let converter: CurrencyConverter

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            SymbolBadge(symbol: account.symbolName, colorHex: account.colorHex, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name).font(.body.weight(.medium)).lineLimit(1)
                    if AppSettings.uuid(forKey: SettingsKey.defaultAccountID) == account.id {
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
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if account.kind.isLiability && balance < 0 {
                    Text(MoneyFormat.string(-balance, code: account.currencyCode))
                        .font(DS.Typography.rowAmount).monospacedDigit()
                        .foregroundStyle(DS.Colors.danger)
                    Text("Owed").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(MoneyFormat.string(balance, code: account.currencyCode))
                        .font(DS.Typography.rowAmount).monospacedDigit()
                        .foregroundStyle(balance < 0 ? DS.Colors.danger : Color.primary)
                    if account.currencyCode != base {
                        if let converted = converter.convert(balance, from: account.currencyCode, to: base) {
                            Text(verbatim: "≈ " + MoneyFormat.string(converted, code: base))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        } else {
                            Text("Pending conversion").font(.caption2).foregroundStyle(DS.Colors.warning)
                        }
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Global add button: tap = new expense; menu = other kinds and page-specific actions.
struct AddMenuButton<Extra: View>: View {
    @Environment(AppRouter.self) private var router
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        Menu {
            Button { router.addEntry(.expense) } label: { Label(TransactionKind.expense.title, systemImage: TransactionKind.expense.symbol) }
            Button { router.addEntry(.income) } label: { Label(TransactionKind.income.title, systemImage: TransactionKind.income.symbol) }
            Button { router.addEntry(.transfer) } label: { Label(TransactionKind.transfer.title, systemImage: TransactionKind.transfer.symbol) }
            Divider()
            extra()
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
        } primaryAction: {
            Haptics.press()
            router.addEntry(.expense)
        }
        .accessibilityLabel(Text("Add Transaction"))
        .accessibilityHint(Text("Tap to record an expense, hold for more options"))
    }
}

extension AddMenuButton where Extra == EmptyView {
    init() { self.init { EmptyView() } }
}
