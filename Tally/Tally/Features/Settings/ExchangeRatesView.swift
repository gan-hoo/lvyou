import SwiftUI
import SwiftData

struct ExchangeRatesView: View {
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @Query(sort: \ExchangeRate.effectiveDate, order: .reverse) private var rates: [ExchangeRate]

    @State private var showAdd = false
    @State private var isFetching = false
    @State private var fetchError: String?

    var body: some View {
        let converter = CurrencyConverter(rates: rates)
        List {
            Section {
                ForEach(CurrencyInfo.all.filter { $0.code != baseCurrency }) { currency in
                    NavigationLink {
                        RateHistoryView(code: currency.code)
                    } label: {
                        RateRow(currency: currency, base: baseCurrency, rate: converter.rate(from: currency.code, to: baseCurrency), latest: latestRecord(for: currency.code))
                    }
                }
            } header: {
                Text("1 unit = \(baseCurrency)")
            } footer: {
                Text("Each transaction uses the most recent rate effective on its own date. Adding a new rate never changes past records.")
            }

            Section {
                Button {
                    showAdd = true
                } label: {
                    Label("Add Rate", systemImage: "plus")
                }
                Button {
                    Task { await fetch() }
                } label: {
                    HStack {
                        Label("Download Today's Rates", systemImage: "arrow.down.circle")
                        Spacer()
                        if isFetching { ProgressView() }
                    }
                }
                .disabled(isFetching)
            } footer: {
                if let fetchError {
                    Text(fetchError).foregroundStyle(DS.Colors.danger)
                } else {
                    Text("Optional. Downloads European Central Bank reference rates (via frankfurter.app). Tally works fully offline without this.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Exchange Rates")
        .sheet(isPresented: $showAdd) {
            AddRateSheet(presetBase: "USD", presetQuote: baseCurrency == "USD" ? "CNY" : baseCurrency)
        }
    }

    private func latestRecord(for code: String) -> ExchangeRate? {
        rates.first { $0.baseCode == code || $0.quoteCode == code }
    }

    private func fetch() async {
        isFetching = true
        fetchError = nil
        defer { isFetching = false }
        do {
            let quotes = try await ExchangeRateFetcher().fetchLatest(base: "USD")
            let store = LedgerStore(context: context)
            for q in quotes {
                store.addRate(base: q.base, quote: q.quote, rate: q.rate, date: q.date, source: ExchangeRate.Source.online)
            }
            Haptics.success()
            toasts.show(ToastMessage(symbol: "checkmark.circle.fill", text: String(localized: "Rates updated"), style: .success))
        } catch {
            Haptics.error()
            fetchError = error.localizedDescription
        }
    }
}

private struct RateRow: View {
    let currency: CurrencyInfo
    let base: String
    let rate: Decimal?
    let latest: ExchangeRate?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(currency.code).font(.body.weight(.semibold))
                Text(currency.localizedName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let rate {
                    Text(verbatim: MoneyFormat.rate(rate) + " " + base)
                        .font(.body.monospacedDigit())
                } else {
                    Text("No rate").foregroundStyle(DS.Colors.warning)
                }
                if let latest {
                    Text(verbatim: RateSource.title(latest.source) + " · " + latest.effectiveDate.shortDateText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

enum RateSource {
    static func title(_ source: String) -> String {
        switch source {
        case ExchangeRate.Source.online: String(localized: "ECB")
        case ExchangeRate.Source.reference: String(localized: "Reference")
        case ExchangeRate.Source.imported: String(localized: "Imported")
        default: String(localized: "Manual")
        }
    }
}

struct RateHistoryView: View {
    let code: String

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @Query(sort: \ExchangeRate.effectiveDate, order: .reverse) private var rates: [ExchangeRate]
    @State private var showAdd = false

    private var history: [ExchangeRate] {
        rates.filter { $0.baseCode == code || $0.quoteCode == code }
    }

    var body: some View {
        List {
            Section {
                ForEach(history) { rate in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "1 \(rate.baseCode) = \(MoneyFormat.rate(rate.rate)) \(rate.quoteCode)")
                                .font(.body.monospacedDigit())
                            Text(verbatim: RateSource.title(rate.source))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(rate.source == ExchangeRate.Source.reference ? String(localized: "Default") : rate.effectiveDate.shortDateText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    let list = history
                    for i in offsets { context.delete(list[i]) }
                    try? context.save()
                }
            } footer: {
                Text("A rate applies from its date until a newer one is added. The default reference rate covers dates before your first entry.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(code)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text("Add Rate"))
            }
        }
        .sheet(isPresented: $showAdd) {
            AddRateSheet(presetBase: code, presetQuote: code == baseCurrency ? "USD" : baseCurrency)
        }
        .overlay {
            if history.isEmpty {
                ContentUnavailableView("No Rates", systemImage: "arrow.left.arrow.right", description: Text("Add a rate to convert this currency."))
            }
        }
    }
}

struct AddRateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var base: String
    @State private var quote: String
    @State private var rateText = ""
    @State private var date = Date.now

    init(presetBase: String, presetQuote: String) {
        _base = State(initialValue: presetBase)
        _quote = State(initialValue: presetQuote)
    }

    private var rate: Decimal? {
        guard let r = DecimalCodec.parseLenient(rateText), r > 0 else { return nil }
        return r
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("From", selection: $base) {
                        ForEach(CurrencyInfo.all) { Text($0.code).tag($0.code) }
                    }
                    Picker("To", selection: $quote) {
                        ForEach(CurrencyInfo.all) { Text($0.code).tag($0.code) }
                    }
                    HStack {
                        Text(verbatim: "1 \(base) =")
                        TextField("Rate", text: $rateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                        Text(quote).foregroundStyle(.secondary)
                    }
                    DatePicker("Effective from", selection: $date, displayedComponents: .date)
                } footer: {
                    if let rate, rate > 0 {
                        Text(verbatim: "1 \(quote) = \(MoneyFormat.rate((Decimal(1) / rate).rounded(scale: 6))) \(base)")
                    }
                }
            }
            .navigationTitle("Add Rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let rate, base != quote else { return }
                        LedgerStore(context: context).addRate(base: base, quote: quote, rate: rate, date: date)
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(rate == nil || base == quote)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
