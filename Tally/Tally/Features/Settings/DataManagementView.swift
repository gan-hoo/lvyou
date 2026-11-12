import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct DataManagementView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppLockManager.self) private var lock
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @Query(sort: \LedgerEntry.date) private var entries: [LedgerEntry]
    @Query private var accounts: [Account]

    @State private var exportRange: TransactionFilter.DateRange = .all
    @State private var shareItem: ShareItem?
    @State private var showImporter = false
    @State private var preview: ImportPreview?
    @State private var importResult: ImportResult?
    @State private var errorMessage: String?
    @State private var confirmDemo = false
    @State private var confirmRemoveDemo = false
    @State private var confirmErase = false

    private var hasDemo: Bool { accounts.contains { $0.isDemo } }

    private var exportEntries: [LedgerEntry] {
        guard let interval = exportRange.interval() else { return entries }
        return entries.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $exportRange) {
                    ForEach(TransactionFilter.DateRange.allCases) { Text($0.title).tag($0) }
                }
                Button {
                    export()
                } label: {
                    HStack {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                        Spacer()
                        Text(exportEntries.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .disabled(exportEntries.isEmpty)
            } header: {
                Text("Export")
            } footer: {
                Text("UTF-8 CSV with original amounts, currencies, the recorded exchange rate and base amount. Opens in Numbers, Excel and Google Sheets.")
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Required columns: Date and Amount. Optional: Type, Currency, Account, To Account, Category, Tags, Note. Chinese headers such as 日期, 金额, 分类 are recognised. Missing accounts and categories are created; duplicates are skipped.")
            }

            Section {
                if hasDemo {
                    Button("Remove Demo Data", role: .destructive) { confirmRemoveDemo = true }
                } else {
                    Button {
                        confirmDemo = true
                    } label: {
                        Label("Load Demo Data", systemImage: "sparkles")
                    }
                }
            } header: {
                Text("Demo")
            } footer: {
                Text("Demo records are clearly marked and can be removed at any time without touching your own data.")
            }

            Section {
                Button("Erase All Data", role: .destructive) { confirmErase = true }
            } footer: {
                Text("Permanently deletes every account, transaction, budget, tag and custom category on this iPhone.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Import & Export")
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .text], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let preview {
                ImportPreviewSheet(preview: preview, base: baseCurrency) {
                    apply(preview)
                }
            }
        }
        .alert("Import Complete", isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } }), presenting: importResult) { _ in
            Button("OK") { importResult = nil }
        } message: { result in
            Text("Imported \(result.imported), skipped \(result.skippedDuplicates) duplicates. Created \(result.createdAccounts) accounts and \(result.createdCategories) categories.")
        }
        .alert("Couldn't Import", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Load demo data?", isPresented: $confirmDemo, titleVisibility: .visible) {
            Button("Load Demo Data") {
                DemoData.load(into: context, base: baseCurrency)
                Haptics.success()
                toasts.show(ToastMessage(symbol: "sparkles", text: String(localized: "Demo data loaded"), style: .success))
            }
        } message: {
            Text("Adds sample accounts and about three months of transactions, all marked as demo.")
        }
        .confirmationDialog("Remove demo data?", isPresented: $confirmRemoveDemo, titleVisibility: .visible) {
            Button("Remove Demo Data", role: .destructive) {
                LedgerStore(context: context).deleteDemoData()
                Haptics.success()
            }
        }
        .confirmationDialog("Erase all data?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive) {
                Task { await erase() }
            }
        } message: {
            Text("This cannot be undone. Consider exporting a CSV first.")
        }
    }

    private func export() {
        do {
            let url = try LedgerCSVExporter.writeFile(for: exportEntries)
            Haptics.tap()
            shareItem = ShareItem(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let text = try LedgerCSVImporter.decodeText(data)
                let parsed = try LedgerCSVImporter.preview(text: text)
                if parsed.rows.isEmpty && !parsed.issues.isEmpty {
                    errorMessage = String(localized: "No valid rows were found in this file.")
                } else {
                    preview = parsed
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ preview: ImportPreview) {
        do {
            let result = try LedgerCSVImporter.apply(preview, context: context, baseCurrency: baseCurrency)
            self.preview = nil
            Haptics.success()
            importResult = result
        } catch {
            self.preview = nil
            errorMessage = error.localizedDescription
        }
    }

    private func erase() async {
        if lock.isEnabled || lock.canAuthenticate {
            guard await lock.authenticate(reason: String(localized: "Confirm to erase all data")) else { return }
        }
        LedgerStore(context: context).eraseAllData()
        Haptics.success()
        toasts.show(ToastMessage(symbol: "trash", text: String(localized: "All data erased")))
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIKit share sheet (AirDrop, Files, Mail, …).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ImportPreviewSheet: View {
    let preview: ImportPreview
    let base: String
    var onImport: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Rows ready", value: preview.rows.count.formatted())
                    LabeledContent("Rows with problems", value: preview.issues.count.formatted())
                    LabeledContent("Columns found", value: preview.recognizedColumns.map(\.rawValue).joined(separator: ", "))
                }

                if !preview.rows.isEmpty {
                    Section("Preview") {
                        ForEach(preview.rows.prefix(8), id: \.line) { row in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.category ?? row.kind.title).font(.subheadline.weight(.medium))
                                    Text(verbatim: row.date.shortDateText + (row.account.isEmpty ? "" : " · " + row.account))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(MoneyFormat.signed(row.amount, code: row.currency ?? base, kind: row.kind))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(DS.Colors.amount(for: row.kind))
                            }
                        }
                    }
                }

                if !preview.issues.isEmpty {
                    Section("Skipped rows") {
                        ForEach(preview.issues.prefix(20)) { issue in
                            LabeledContent(String(localized: "Line \(issue.line)"), value: issue.message)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Import Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { onImport() }
                        .fontWeight(.semibold)
                        .disabled(preview.rows.isEmpty)
                }
            }
        }
    }
}
