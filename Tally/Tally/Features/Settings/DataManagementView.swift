import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

enum ExportRange: String, CaseIterable, Identifiable {
    case all, thisMonth, lastMonth, thisYear, lastYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All Time")
        case .thisMonth: String(localized: "This Month")
        case .lastMonth: String(localized: "Last Month")
        case .thisYear: String(localized: "This Year")
        case .lastYear: String(localized: "Last Year")
        }
    }

    var period: Period? {
        switch self {
        case .all: nil
        case .thisMonth: .month()
        case .lastMonth: Period.month().previous
        case .thisYear: .year()
        case .lastYear: Period.year().previous
        }
    }
}

struct DataManagementView: View {
    private enum PickedFile { case csv, backup }

    @Environment(\.modelContext) private var context
    @Environment(AppLockManager.self) private var lock
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @Query(sort: \LedgerEntry.date) private var entries: [LedgerEntry]
    @Query private var accounts: [Account]

    @State private var exportRange: ExportRange = .all
    @State private var shareItem: ShareItem?
    @State private var picking: PickedFile = .csv
    @State private var showImporter = false
    @State private var preview: ImportPreview?
    @State private var importResult: ImportResult?
    @State private var backupFile: BackupService.File?
    @State private var restoreSummary: BackupService.RestoreSummary?
    @State private var errorMessage: String?
    @State private var confirmDemo = false
    @State private var confirmRemoveDemo = false
    @State private var confirmErase = false

    private var hasDemo: Bool { accounts.contains { $0.isDemo } }

    private var exportEntries: [LedgerEntry] {
        guard let period = exportRange.period else { return entries }
        return entries.filter { period.contains($0.date) }
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $exportRange) {
                    ForEach(ExportRange.allCases) { Text($0.title).tag($0) }
                }
                Button(action: exportCSV) {
                    HStack {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                        Spacer()
                        Text(exportEntries.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .disabled(exportEntries.isEmpty)
                Button {
                    picking = .csv
                    showImporter = true
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("CSV")
            } footer: {
                Text("Exports original amounts, currencies, the saved exchange rate, splits, payee and fees. Import needs Date and Amount columns; Chinese headers such as 日期, 金额, 分类 are recognised. Foreign-currency rows without an exchange rate are not imported. Duplicates are skipped.")
            }

            Section {
                Button(action: createBackup) {
                    Label("Create Backup", systemImage: "externaldrive.badge.plus")
                }
                Button {
                    picking = .backup
                    showImporter = true
                } label: {
                    Label("Restore from Backup", systemImage: "externaldrive.badge.timemachine")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("A backup is one JSON file with every account, transaction, budget, recurring plan and exchange rate, plus a checksum. Save it to Files or iCloud Drive. Restoring shows what the file contains before anything changes.")
            }

            Section {
                NavigationLink {
                    IntegrityView()
                } label: {
                    Label("Check Data Integrity", systemImage: "checkmark.shield")
                }
                NavigationLink {
                    AuditLogView()
                } label: {
                    Label("Change History", systemImage: "clock.arrow.circlepath")
                }
            } header: {
                Text("Maintenance")
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
                Text("Demo records are marked and can be removed at any time without touching your own data.")
            }

            Section {
                Button("Erase All Data", role: .destructive) { confirmErase = true }
            } footer: {
                Text("Permanently deletes every account, transaction, budget, tag and custom category on this iPhone.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Data")
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: picking == .csv ? [.commaSeparatedText, .plainText, .text] : [.json],
            allowsMultipleSelection: false
        ) { result in
            handlePicked(result)
        }
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let preview {
                ImportPreviewSheet(preview: preview, base: baseCurrency) {
                    apply(preview)
                }
            }
        }
        .sheet(isPresented: Binding(get: { backupFile != nil }, set: { if !$0 { backupFile = nil } })) {
            if let backupFile {
                RestorePreviewSheet(file: backupFile) { mode in
                    Task { await restore(backupFile, mode: mode) }
                }
            }
        }
        .alert("Import Complete", isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } }), presenting: importResult) { _ in
            Button("OK") { importResult = nil }
        } message: { result in
            Text(importMessage(result))
        }
        .alert("Restore Complete", isPresented: Binding(get: { restoreSummary != nil }, set: { if !$0 { restoreSummary = nil } }), presenting: restoreSummary) { _ in
            Button("OK") { restoreSummary = nil }
        } message: { summary in
            Text("Added \(summary.added) records, skipped \(summary.skipped) already in the ledger.")
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
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
                do {
                    try LedgerRepository(context: context).deleteDemoData()
                    Haptics.success()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog("Erase all data?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive) {
                Task { await erase() }
            }
        } message: {
            Text("This cannot be undone. Consider creating a backup first.")
        }
    }

    private func importMessage(_ r: ImportResult) -> String {
        var text = String(localized: "Imported \(r.imported), skipped \(r.skippedDuplicates) duplicates. Created \(r.createdAccounts) accounts and \(r.createdCategories) categories.")
        if !r.failed.isEmpty {
            let lines = r.failed.prefix(3).map { String(localized: "Line \($0.line)") + ": " + $0.message }
            text += "\n" + String(localized: "\(r.failed.count) rows were not imported:") + "\n" + lines.joined(separator: "\n")
        }
        return text
    }

    // MARK: Export

    private func exportCSV() {
        do {
            let url = try LedgerCSVExporter.writeFile(for: exportEntries)
            Haptics.tap()
            shareItem = ShareItem(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createBackup() {
        do {
            let url = try BackupService(context: context).writeBackupFile()
            Haptics.tap()
            shareItem = ShareItem(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Import

    private func handlePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                switch picking {
                case .csv:
                    let text = try LedgerCSVImporter.decodeText(data)
                    let parsed = try LedgerCSVImporter.preview(text: text)
                    if parsed.rows.isEmpty && !parsed.issues.isEmpty {
                        errorMessage = String(localized: "No valid rows were found in this file.")
                    } else {
                        preview = parsed
                    }
                case .backup:
                    backupFile = try BackupService.read(data)
                }
            } catch {
                Haptics.error()
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

    private func restore(_ file: BackupService.File, mode: BackupService.RestoreMode) async {
        backupFile = nil
        if mode == .replace && (lock.isEnabled || lock.canAuthenticate) {
            guard await lock.authenticate(reason: String(localized: "Confirm to replace all data")) else { return }
        }
        do {
            restoreSummary = try BackupService(context: context).restore(file, mode: mode)
            Haptics.success()
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
    }

    private func erase() async {
        if lock.isEnabled || lock.canAuthenticate {
            guard await lock.authenticate(reason: String(localized: "Confirm to erase all data")) else { return }
        }
        do {
            try LedgerRepository(context: context).eraseAllData()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        Haptics.success()
        toasts.show(ToastMessage(symbol: "trash", text: String(localized: "All data erased")))
        // Start over from the welcome screen so a main currency and first accounts can be chosen again.
        UserDefaults.standard.set(false, forKey: SettingsKey.hasCompletedOnboarding)
    }
}

/// Shows what a backup contains and how it will be restored before anything changes.
struct RestorePreviewSheet: View {
    let file: BackupService.File
    var onRestore: (BackupService.RestoreMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var replace = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Created", value: file.createdAt.text(date: .abbreviated, time: .shortened))
                    LabeledContent("App version", value: file.appVersion)
                    LabeledContent("Format version", value: file.schemaVersion.formatted())
                    LabeledContent("Checksum") {
                        Label("Verified", systemImage: "checkmark.seal.fill").foregroundStyle(DS.Colors.income)
                    }
                }
                Section("Contents") {
                    LabeledContent("Accounts", value: file.payload.accounts.count.formatted())
                    LabeledContent("Transactions", value: file.payload.entries.count.formatted())
                    LabeledContent("Categories", value: file.payload.categories.count.formatted())
                    LabeledContent("Budgets", value: file.payload.budgets.count.formatted())
                    LabeledContent("Recurring Plans", value: file.payload.rules.count.formatted())
                    LabeledContent("Exchange Rates", value: file.payload.rates.count.formatted())
                }
                Section {
                    Picker("Mode", selection: $replace) {
                        Text("Merge").tag(false)
                        Text("Replace").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if replace {
                        Text("Replace erases everything on this iPhone first, then restores the backup.")
                            .foregroundStyle(DS.Colors.danger)
                    } else {
                        Text("Merge adds records from the backup that aren't in the ledger yet. Existing records are left as they are.")
                    }
                }
            }
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(replace ? String(localized: "Replace") : String(localized: "Merge"), role: replace ? .destructive : nil) {
                        onRestore(replace ? .replace : .merge)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

/// Runs the integrity check and offers safe repairs.
struct IntegrityView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.baseCurrency) private var baseCurrency: String = CurrencyInfo.suggestedBase
    @State private var report: IntegrityService.Report?
    @State private var repaired: Int?

    var body: some View {
        List {
            if let report {
                Section {
                    HStack(spacing: DS.Spacing.m) {
                        Image(systemName: report.isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(report.isHealthy ? DS.Colors.income : DS.Colors.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.isHealthy ? "No problems found" : "\(report.issues.count) items need attention")
                                .font(.headline)
                            Text("Checked \(report.checkedEntries) transactions").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !report.issues.isEmpty {
                    let groups = Dictionary(grouping: report.issues, by: \.kind)
                    ForEach(groups.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { kind in
                        Section(groups[kind]?.first?.title ?? "") {
                            ForEach((groups[kind] ?? []).prefix(50)) { issue in
                                Text(verbatim: issue.detail).font(.footnote)
                            }
                        }
                    }
                    Section {
                        Button {
                            repaired = IntegrityService(context: context).repair(base: baseCurrency)
                            run()
                        } label: {
                            Label("Repair What Can Be Fixed", systemImage: "wrench.and.screwdriver")
                        }
                    } footer: {
                        Text("Repair fills in exchange rates for transactions that were waiting for one and pauses recurring plans whose account was deleted. Other items are listed so you can fix them yourself.")
                    }
                }
                if let repaired {
                    Section { Text("Fixed \(repaired) items.").foregroundStyle(.secondary) }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Data Integrity")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { run() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel(Text("Check Again"))
            }
        }
        .onAppear(perform: run)
    }

    private func run() {
        report = IntegrityService(context: context).run(base: baseCurrency)
    }
}

/// Read-only list of recorded changes (adjustments, deletions, imports, restores).
struct AuditLogView: View {
    @Query(sort: \AuditRecord.date, order: .reverse) private var records: [AuditRecord]

    var body: some View {
        List {
            Section {
                ForEach(records.prefix(500)) { r in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(verbatim: AuditText.title(r)).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(r.date.text(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(verbatim: r.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("Tally records balance adjustments, deletions, imports and restores so changes to your money can be traced.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Change History")
        .overlay {
            if records.isEmpty {
                ContentUnavailableView("No Changes Yet", systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

enum AuditText {
    static func title(_ r: AuditRecord) -> String {
        let action: String
        switch r.action {
        case AuditRecord.Action.create: action = String(localized: "Created")
        case AuditRecord.Action.update: action = String(localized: "Edited")
        case AuditRecord.Action.delete: action = String(localized: "Deleted")
        case AuditRecord.Action.adjust: action = String(localized: "Balance adjusted")
        case AuditRecord.Action.restore: action = String(localized: "Restored")
        case AuditRecord.Action.importCSV: action = String(localized: "Imported")
        default: action = r.action
        }
        let entity: String
        switch r.entityKind {
        case "entry": entity = String(localized: "Transaction")
        case "account": entity = String(localized: "Account")
        case "budget": entity = String(localized: "Budget")
        case "category": entity = String(localized: "Category")
        case "backup": entity = String(localized: "Backup")
        case "csv": entity = String(localized: "CSV")
        case "rule": entity = String(localized: "Recurring Plan")
        default: entity = r.entityKind
        }
        return action + " · " + entity
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
