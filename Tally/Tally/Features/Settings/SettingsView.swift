import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppLockManager.self) private var lock
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @AppStorage(SettingsKey.appearance) private var appearance: String = AppearanceMode.system.rawValue
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKey.budgetAlertsEnabled) private var budgetAlerts = true

    @Query private var accounts: [Account]
    @Query private var categories: [LedgerCategory]
    @Query private var tags: [Tag]
    @Query private var entries: [LedgerEntry]

    @State private var lockToggleBusy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(selection: $baseCurrency) {
                        ForEach(CurrencyInfo.all) { c in
                            Text(verbatim: "\(c.code) · \(c.localizedName)").tag(c.code)
                        }
                    } label: {
                        SettingsLabel("Main currency", symbol: "coloncurrencysign.circle", color: "3BB5A6")
                    }
                    Picker(selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode.rawValue)
                        }
                    } label: {
                        SettingsLabel("Appearance", symbol: "circle.lefthalf.filled", color: "5B6573")
                    }
                    Toggle(isOn: $hapticsEnabled) {
                        SettingsLabel("Haptic feedback", symbol: "hand.tap", color: "F2994A")
                    }
                    Toggle(isOn: $budgetAlerts) {
                        SettingsLabel("Budget reminders", symbol: "bell.badge", color: "EB5757")
                    }
                } header: {
                    Text("General")
                } footer: {
                    Text("Totals, statistics and budgets use the main currency. Each transaction keeps its original amount and the rate used on its date.")
                }

                Section("Ledger") {
                    NavigationLink {
                        AccountsListView()
                    } label: {
                        SettingsLabel("Accounts", symbol: "wallet.pass", color: "3E7BFA", detail: accounts.count.formatted())
                    }
                    NavigationLink {
                        CategoryListView(initialKind: .expense)
                    } label: {
                        SettingsLabel("Categories", symbol: "square.grid.2x2", color: "9B6DD6", detail: categories.count.formatted())
                    }
                    NavigationLink {
                        TagListView()
                    } label: {
                        SettingsLabel("Tags", symbol: "number", color: "47B5D9", detail: tags.count.formatted())
                    }
                    NavigationLink {
                        ExchangeRatesView()
                    } label: {
                        SettingsLabel("Exchange rates", symbol: "arrow.left.arrow.right", color: "4CB782")
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { lock.isEnabled },
                        set: { newValue in
                            lockToggleBusy = true
                            Task {
                                await lock.setEnabled(newValue)
                                lockToggleBusy = false
                            }
                        }
                    )) {
                        SettingsLabel("Lock with \(lock.biometry.title)", symbol: lock.biometry.symbol, color: "4CB782")
                    }
                    .disabled(lockToggleBusy)

                    if lock.isEnabled {
                        Picker(selection: Binding(get: { lock.gracePeriod }, set: { lock.setGracePeriod($0) })) {
                            ForEach(LockGracePeriod.allCases) { p in Text(p.title).tag(p) }
                        } label: {
                            SettingsLabel("Require unlock", symbol: "timer", color: "7D8BA6")
                        }
                    }
                    Toggle(isOn: Binding(get: { lock.privacyCover }, set: { lock.setPrivacyCover($0) })) {
                        SettingsLabel("Hide in App Switcher", symbol: "eye.slash", color: "5B6573")
                    }
                } header: {
                    Text("Privacy & Security")
                } footer: {
                    if let error = lock.lastError {
                        Text(error).foregroundStyle(DS.Colors.danger)
                    } else {
                        Text("Lock settings are stored in the Keychain. If biometrics fail, your device passcode can unlock Tally.")
                    }
                }

                Section("Data") {
                    NavigationLink {
                        DataManagementView()
                    } label: {
                        SettingsLabel("Import & Export", symbol: "arrow.up.arrow.down.square", color: "E8B730", detail: entries.count.formatted())
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    Text("Tally keeps all data on this iPhone. Nothing is sent anywhere unless you export it or choose to download exchange rates.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationDestination(for: LedgerEntry.self) { TransactionDetailView(entry: $0) }
            .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
        }
    }
}

/// iOS Settings-style row label with a solid rounded icon.
struct SettingsLabel: View {
    var title: LocalizedStringKey
    var symbol: String
    var color: String
    var detail: String?

    init(_ title: LocalizedStringKey, symbol: String, color: String, detail: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.color = color
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            SymbolBadge(symbol: symbol, colorHex: color, size: 30, style: .solid)
            Text(title)
            if let detail {
                Spacer()
                Text(detail).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
