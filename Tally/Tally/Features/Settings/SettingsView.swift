import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(AppLockManager.self) private var lock
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @AppStorage(SettingsKey.appearance) private var appearance: String = AppearanceMode.system.rawValue
    @AppStorage(SettingsKey.theme) private var theme: String = ThemeStyle.classic.rawValue
    @AppStorage(SettingsKey.accent) private var accent: String = "3E7BFA"
    @AppStorage(SettingsKey.amountStyle) private var amountStyle: String = AmountStyle.symbol.rawValue
    @AppStorage(SettingsKey.hideAmounts) private var hideAmounts = false
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKey.budgetAlertsEnabled) private var budgetAlerts = true
    @AppStorage(SettingsKey.budgetStartDay) private var budgetStartDay = 1
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID: String = ""

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var categories: [LedgerCategory]
    @Query private var tags: [Tag]
    @Query private var rules: [RecurringRule]

    @State private var lockToggleBusy = false

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                financeSection
                dataSection
                privacySection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .pageBackground()
            .tabRootTitle("Settings")
            .navigationDestination(for: LedgerEntry.self) { TransactionDetailView(entry: $0) }
            .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section {
            Picker(selection: $theme) {
                ForEach(ThemeStyle.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                SettingsLabel("Theme", symbol: "paintpalette", color: "5856D6")
            }
            Picker(selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode.rawValue)
                }
            } label: {
                SettingsLabel("Appearance", symbol: "circle.lefthalf.filled", color: "5B6573")
            }
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                SettingsLabel("Accent Color", symbol: "drop", color: accent)
                HStack(spacing: 0) {
                    ForEach(DS.Colors.accentChoices, id: \.self) { hex in
                        Button {
                            Haptics.selection()
                            accent = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(.white, lineWidth: accent == hex ? 3 : 0))
                                .overlay(Circle().strokeBorder(Color(hex: hex), lineWidth: accent == hex ? 1.5 : 0).padding(-3))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: "#" + hex))
                        .accessibilityAddTraits(accent == hex ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 4)
            Picker(selection: $amountStyle) {
                ForEach(AmountStyle.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                SettingsLabel("Amount Format", symbol: "textformat.123", color: "E8932A")
            }
            LanguageMenu { language in
                HStack {
                    SettingsLabel("Language", symbol: "globe", color: "4A90E2")
                    Spacer()
                    Text(verbatim: language.title).foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .tint(.primary)
            Toggle(isOn: $hapticsEnabled) {
                SettingsLabel("Haptic Feedback", symbol: "hand.tap", color: "F2994A")
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Liquid Glass uses the system glass material on iOS 26 and a translucent material on earlier versions. Both themes share the same pages.")
        }
    }

    // MARK: Finance

    private var financeSection: some View {
        Section {
            Picker(selection: $baseCurrency) {
                ForEach(CurrencyInfo.all) { c in
                    Text(verbatim: "\(c.code) · \(c.localizedName)").tag(c.code)
                }
            } label: {
                SettingsLabel("Base Currency", symbol: "coloncurrencysign.circle", color: "3BB5A6")
            }
            NavigationLink {
                ExchangeRatesView()
            } label: {
                SettingsLabel("Exchange Rates", symbol: "arrow.left.arrow.right", color: "4CB782")
            }
            Button {
                router.show(.assets)
            } label: {
                HStack {
                    SettingsLabel("Accounts", symbol: "wallet.pass", color: "3E7BFA", detail: accounts.filter { !$0.isArchived }.count.formatted())
                    Image(systemName: "arrow.up.forward").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
            Picker(selection: $defaultAccountID) {
                Text("Last Used").tag("")
                ForEach(accounts.filter { !$0.isArchived }) { a in
                    Text(a.name).tag(a.id.uuidString)
                }
            } label: {
                SettingsLabel("Default Account", symbol: "star", color: "E8B730")
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
                RecurringListView()
            } label: {
                SettingsLabel("Recurring Plans", symbol: "repeat", color: "EB5E8C", detail: rules.filter(\.isActive).count.formatted())
            }
            Picker(selection: $budgetStartDay) {
                ForEach(1...28, id: \.self) { day in Text(day.formatted()).tag(day) }
            } label: {
                SettingsLabel("Budget Month Starts On", symbol: "calendar", color: "E5534B")
            }
            Toggle(isOn: $budgetAlerts) {
                SettingsLabel("Budget Alerts", symbol: "bell.badge", color: "EB5757")
            }
        } header: {
            Text("Finance")
        } footer: {
            Text("Totals, analytics and budgets are shown in the base currency. Each transaction keeps its original amount, currency and the rate saved on its date; amounts without a rate are marked as pending and never counted at 1:1.")
        }
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            NavigationLink {
                DataManagementView()
            } label: {
                SettingsLabel("Import, Export & Backup", symbol: "externaldrive", color: "E8B730")
            }
            NavigationLink {
                IntegrityView()
            } label: {
                SettingsLabel("Data Integrity", symbol: "checkmark.shield", color: "16A06A")
            }
        } header: {
            Text("Data")
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
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
                    SettingsLabel("Auto-Lock", symbol: "timer", color: "7D8BA6")
                }
            }
            Toggle(isOn: Binding(get: { lock.privacyCover }, set: { lock.setPrivacyCover($0) })) {
                SettingsLabel("Hide in App Switcher", symbol: "rectangle.on.rectangle.slash", color: "5B6573")
            }
            Toggle(isOn: $hideAmounts) {
                SettingsLabel("Hide Amounts", symbol: "eye.slash", color: "8E8E93")
            }
        } header: {
            Text("Privacy & Security")
        } footer: {
            if let error = lock.lastError {
                Text(error).foregroundStyle(DS.Colors.danger)
            } else {
                Text("Lock settings are stored in the Keychain. If Face ID fails, your device passcode can unlock Tally. Hide Amounts masks balances on every page until you turn it off.")
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(Bundle.main.versionString).monospacedDigit()
            } label: {
                SettingsLabel("Version", symbol: "info.circle", color: "8E8E93")
            }
            NavigationLink {
                WhatsNewView()
            } label: {
                SettingsLabel("What's New & Updates", symbol: "sparkles", color: "3E7BFA")
            }
            NavigationLink {
                PrivacyNoteView()
            } label: {
                SettingsLabel("Privacy", symbol: "hand.raised", color: "4CB782")
            }
            NavigationLink {
                LicensesView()
            } label: {
                SettingsLabel("Acknowledgements", symbol: "doc.text", color: "7D8BA6")
            }
            NavigationLink {
                FeedbackView()
            } label: {
                SettingsLabel("Feedback", symbol: "envelope", color: "E8932A")
            }
        } header: {
            Text("About")
        } footer: {
            Text("Tally keeps all data on this iPhone. Nothing is sent anywhere unless you export it or choose to download exchange rates.")
        }
    }
}

// MARK: - About pages

struct WhatsNewView: View {
    var body: some View {
        List {
            Section {
                Text("Installed outside the App Store, Tally does not update itself. A newer version arrives as a new IPA file; installing it over this one keeps your data. Create a backup before updating.")
                    .font(.subheadline)
            } header: {
                Text("Updates")
            }
            Section(Bundle.main.versionString) {
                bullet("Five tabs: Assets, Transactions, Analytics, Budgets and Settings. Assets opens first.")
                bullet("Net worth with assets and liabilities, credit cards and loans, opening dates, reconciliation and audited balance adjustments.")
                bullet("Transfers with fees and different amounts on each side, refunds linked to the original purchase, split transactions and credit-card repayments.")
                bullet("Recurring plans that book each occurrence once, only when it is due.")
                bullet("Analytics by week, month, year or custom range with comparisons, category drill-down and trends.")
                bullet("Weekly, monthly, yearly and custom budgets with roll-over, exclusions, daily allowance and alerts.")
                bullet("Classic and Liquid Glass themes, accent colors, amount formats and Hide Amounts.")
                bullet("Backups with checksum and version check, data integrity check and change history.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("What's New")
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
            Image(systemName: "checkmark.circle.fill").font(.footnote).foregroundStyle(DS.Colors.accent)
            Text(text).font(.subheadline)
        }
    }
}

struct PrivacyNoteView: View {
    var body: some View {
        List {
            Section {
                Text("Your ledger is stored only in this app's private storage on this iPhone. Tally has no account, no analytics and no advertising.")
                Text("The network is used only when you tap Download Today's Rates, which requests public reference rates from frankfurter.app. No ledger data is sent.")
                Text("Exports and backups are files you choose where to save. They are not encrypted — keep them somewhere safe.")
                Text("Face ID data never leaves the Secure Enclave; Tally only receives a yes/no answer from iOS.")
            }
            .font(.subheadline)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Privacy")
    }
}

struct LicensesView: View {
    var body: some View {
        List {
            Section {
                Text("Tally is built only with Apple frameworks: SwiftUI, SwiftData, Swift Charts, LocalAuthentication, CryptoKit and Security. No third-party code is included in the app.")
            }
            Section("Data") {
                Text("Optional exchange rates: European Central Bank reference rates, served by the Frankfurter API (frankfurter.app).")
            }
            Section("Tools") {
                Text("Traditional Chinese text was converted at build time with OpenCC (Apache License 2.0). OpenCC is not part of the app.")
            }
        }
        .font(.subheadline)
        .listStyle(.insetGrouped)
        .navigationTitle("Acknowledgements")
    }
}

/// Collects diagnostic details (never ledger contents) that can be pasted into a report.
struct FeedbackView: View {
    @Query private var entries: [LedgerEntry]
    @Query private var accounts: [Account]

    private var diagnostics: String {
        [
            "Tally \(Bundle.main.versionString)",
            "iOS \(UIDevice.current.systemVersion)",
            "\(UIDevice.current.model)",
            "Language: \(Locale.preferredLanguages.first ?? "-")",
            "Theme: \(AppSettings.theme.rawValue)",
            "Accounts: \(accounts.count), Transactions: \(entries.count)",
        ].joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                Text(verbatim: diagnostics)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                ShareLink(item: diagnostics) {
                    Label("Share Diagnostics", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = diagnostics
                    Haptics.success()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            } footer: {
                Text("Include these details when you report a problem. They contain no amounts, names or notes.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Feedback")
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
