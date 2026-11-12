import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.hasCompletedOnboarding) private var onboarded = false
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @State private var appeared = false
    @State private var isLoading = false

    private let features: [(String, LocalizedStringKey, LocalizedStringKey)] = [
        ("bolt", "Record in seconds", "A calculator keypad and smart defaults keep everyday entries to two or three taps."),
        ("globe", "Every currency, every rate", "Original amounts and historical exchange rates are stored separately, so past records never drift."),
        ("lock.shield", "Private by design", "Everything stays on this iPhone, protected by Face ID."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    AppGlyph(size: 64)
                    Text("Welcome to Tally")
                        .font(.largeTitle.weight(.bold))
                    Text("A calm, precise ledger for everyday money.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                        HStack(alignment: .top, spacing: DS.Spacing.l) {
                            Image(systemName: feature.0)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(DS.Colors.accent)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.1).font(.headline)
                                Text(feature.2).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                        .animation(DS.Motion.adaptive(DS.Motion.gentle.delay(0.08 * Double(index))), value: appeared)
                    }
                }

                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    Text("Main currency")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Picker("Main currency", selection: $baseCurrency) {
                        ForEach(CurrencyInfo.all) { c in
                            Text(verbatim: "\(c.code) · \(c.localizedName)").tag(c.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: DS.Spacing.s, radius: DS.Radius.inner)
                    Text("Totals, statistics and budgets are shown in this currency. You can change it later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: DS.Spacing.m) {
                Button {
                    start(withDemo: false)
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)

                Button {
                    start(withDemo: true)
                } label: {
                    Text("Explore with demo data")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderless)
            }
            .disabled(isLoading)
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .background(DS.Colors.background.ignoresSafeArea())
        .onAppear { appeared = true }
    }

    private func start(withDemo: Bool) {
        isLoading = true
        DefaultData.ensureSeeded(in: context)
        if withDemo {
            DemoData.load(into: context, base: baseCurrency)
        } else {
            let existing = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
            if existing == 0 {
                let cash = Account(name: String(localized: "Cash"), kind: .cash, currencyCode: baseCurrency, colorHex: "4CB782")
                let card = Account(name: String(localized: "Bank Card"), kind: .debitCard, currencyCode: baseCurrency, colorHex: "3E7BFA", sortOrder: 1)
                context.insert(cash)
                context.insert(card)
                try? context.save()
                AppSettings.setUUID(card.id, forKey: SettingsKey.defaultAccountID)
            }
        }
        Haptics.success()
        isLoading = false
        onboarded = true
    }
}
