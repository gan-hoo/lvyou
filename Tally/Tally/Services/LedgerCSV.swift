import Foundation
import SwiftData

// MARK: - Export

enum LedgerCSVExporter {
    static func rows(for entries: [LedgerEntry]) -> [[String]] {
        var rows: [[String]] = [LedgerCSVColumn.allCases.map(\.rawValue)]
        for e in entries.sorted(by: { $0.date < $1.date }) {
            rows.append(row(for: e))
        }
        return rows
    }

    private static func row(for e: LedgerEntry) -> [String] {
        let isTransfer = e.kind == .transfer
        let toName: String = isTransfer ? (e.toAccount?.name ?? "") : ""
        let toAmount: String = (isTransfer && !e.toAmountRaw.isEmpty) ? DecimalCodec.encode(e.toAmount) : ""
        let toCurrency: String = isTransfer ? (e.toAccount?.currencyCode ?? "") : ""
        let category: String = isTransfer ? "" : (e.category?.name ?? "")
        let tags: String = e.tagList.map(\.name).joined(separator: "; ")
        var fields: [String] = []
        fields.append(CSVDate.exportFormatter.string(from: e.date))
        fields.append(e.kind.rawValue)
        fields.append(DecimalCodec.encode(e.amount))
        fields.append(e.currencyCode)
        fields.append(e.account?.name ?? "")
        fields.append(toName)
        fields.append(toAmount)
        fields.append(toCurrency)
        fields.append(category)
        fields.append(tags)
        fields.append(e.note)
        fields.append(e.baseCurrencyCode)
        fields.append(e.rateToBaseRaw)
        fields.append(e.baseAmountRaw)
        fields.append(e.id.uuidString)
        return fields
    }

    static func csvString(for entries: [LedgerEntry]) -> String {
        CSVCodec.serialize(rows(for: entries))
    }

    /// Writes a UTF-8 (with BOM, so Excel/Numbers detect Chinese correctly) CSV into a temp folder.
    static func writeFile(for entries: [LedgerEntry], now: Date = .now) throws -> URL {
        let stamp = now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tally-\(stamp).csv")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csvString(for: entries).utf8))
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Import

struct ImportRow: Equatable {
    var line: Int
    var date: Date
    var kind: TransactionKind
    var amount: Decimal
    var currency: String?
    var account: String
    var toAccount: String?
    var toAmount: Decimal?
    var toCurrency: String?
    var category: String?
    var tags: [String]
    var note: String
    var id: UUID?
}

struct ImportIssue: Identifiable, Equatable {
    var id: Int { line }
    let line: Int
    let message: String
}

struct ImportPreview {
    var rows: [ImportRow] = []
    var issues: [ImportIssue] = []
    var recognizedColumns: [LedgerCSVColumn] = []

    var isUsable: Bool { !rows.isEmpty }
}

struct ImportResult: Equatable {
    var imported = 0
    var skippedDuplicates = 0
    var createdAccounts = 0
    var createdCategories = 0
}

enum LedgerCSVImporter {
    enum ImportFailure: LocalizedError {
        case unreadable
        case missingColumns

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "The file could not be read as UTF-8 text.")
            case .missingColumns: String(localized: "The file needs at least Date and Amount columns.")
            }
        }
    }

    static func decodeText(_ data: Data) throws -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        // GB18030 covers files exported by many Chinese banking / bookkeeping apps.
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: gb)) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        throw ImportFailure.unreadable
    }

    static func preview(text: String) throws -> ImportPreview {
        let table = CSVCodec.parse(text)
        guard let header = table.first else { throw ImportFailure.missingColumns }

        var index: [LedgerCSVColumn: Int] = [:]
        for (i, raw) in header.enumerated() {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            for column in LedgerCSVColumn.allCases where index[column] == nil {
                if column.rawValue.lowercased() == name || column.aliases.contains(name) {
                    index[column] = i
                    break
                }
            }
        }
        guard index[.date] != nil, index[.amount] != nil else { throw ImportFailure.missingColumns }

        var preview = ImportPreview()
        preview.recognizedColumns = LedgerCSVColumn.allCases.filter { index[$0] != nil }

        for (offset, fields) in table.dropFirst().enumerated() {
            let line = offset + 2
            func value(_ c: LedgerCSVColumn) -> String {
                guard let i = index[c], i < fields.count else { return "" }
                return fields[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let date = CSVDate.parse(value(.date)) else {
                preview.issues.append(ImportIssue(line: line, message: String(localized: "Unrecognized date")))
                continue
            }
            guard let signed = DecimalCodec.parseLenient(value(.amount)), signed != 0 else {
                preview.issues.append(ImportIssue(line: line, message: String(localized: "Invalid amount")))
                continue
            }

            let kind = parseKind(value(.type), signedAmount: signed)
            let toAccount = value(.toAccount)
            if kind == .transfer && toAccount.isEmpty {
                preview.issues.append(ImportIssue(line: line, message: String(localized: "Transfer without destination account")))
                continue
            }

            let currency = value(.currency).uppercased()
            let tags = value(.tags)
                .split(whereSeparator: { tagSeparators.contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            preview.rows.append(ImportRow(
                line: line,
                date: date,
                kind: kind,
                amount: signed.magnitudeValue,
                currency: currency.isEmpty ? nil : currency,
                account: value(.account),
                toAccount: toAccount.isEmpty ? nil : toAccount,
                toAmount: DecimalCodec.parseLenient(value(.toAmount))?.magnitudeValue,
                toCurrency: value(.toCurrency).isEmpty ? nil : value(.toCurrency).uppercased(),
                category: value(.category).isEmpty ? nil : value(.category),
                tags: tags,
                note: value(.note),
                id: UUID(uuidString: value(.id))
            ))
        }
        return preview
    }

    private static let tagSeparators: Set<Character> = [";", "|", "，", "；"]

    static func parseKind(_ raw: String, signedAmount: Decimal) -> TransactionKind {
        switch raw.lowercased() {
        case "expense", "支出", "out", "outflow", "debit", "spend", "消费": return .expense
        case "income", "收入", "in", "inflow", "credit", "入账": return .income
        case "transfer", "转账", "transfer out", "内部转账": return .transfer
        default: return signedAmount < 0 ? .expense : (raw.isEmpty ? .income : .expense)
        }
    }

    /// Writes the preview's rows into the store. Re-importing Tally's own export is
    /// idempotent: rows whose ID already exists — or that exactly duplicate an
    /// existing entry — are skipped.
    @MainActor
    static func apply(_ preview: ImportPreview, context: ModelContext, baseCurrency: String = AppSettings.baseCurrency) throws -> ImportResult {
        let store = LedgerStore(context: context)
        let converter = store.converter()
        var result = ImportResult()

        var accounts = Dictionary(
            ((try? context.fetch(FetchDescriptor<Account>())) ?? []).map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var categories = Dictionary(
            ((try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? []).map { ($0.kindRaw + "|" + $0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var tags = Dictionary(
            ((try? context.fetch(FetchDescriptor<Tag>())) ?? []).map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existing = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        var knownIDs = Set(existing.map(\.id))
        var signatures = Set(existing.map { signature($0) })

        var nextAccountOrder = store.nextAccountSortOrder()
        let fallbackAccountName = String(localized: "Imported")

        func account(named raw: String, currency: String?) -> Account {
            let name = raw.isEmpty ? fallbackAccountName : raw
            if let a = accounts[name.lowercased()] { return a }
            let a = Account(
                name: name,
                kind: .debitCard,
                currencyCode: currency ?? baseCurrency,
                colorHex: DS.Palette.swatches[nextAccountOrder % DS.Palette.swatches.count],
                sortOrder: nextAccountOrder
            )
            nextAccountOrder += 1
            context.insert(a)
            accounts[name.lowercased()] = a
            result.createdAccounts += 1
            return a
        }

        func category(named name: String?, kind: TransactionKind) -> LedgerCategory? {
            guard let name, let catKind = kind.categoryKind else { return nil }
            let key = catKind.rawValue + "|" + name.lowercased()
            if let c = categories[key] { return c }
            let c = LedgerCategory(
                name: name,
                kind: catKind,
                symbolName: "tag",
                colorHex: DS.Palette.swatches[categories.count % DS.Palette.swatches.count],
                sortOrder: store.nextCategorySortOrder(kind: catKind)
            )
            context.insert(c)
            categories[key] = c
            result.createdCategories += 1
            return c
        }

        func tag(named name: String) -> Tag {
            if let t = tags[name.lowercased()] { return t }
            let t = Tag(name: name, colorHex: DS.Palette.swatches[tags.count % DS.Palette.swatches.count])
            context.insert(t)
            tags[name.lowercased()] = t
            return t
        }

        for row in preview.rows {
            if let id = row.id, knownIDs.contains(id) {
                result.skippedDuplicates += 1
                continue
            }
            let source = account(named: row.account, currency: row.currency)
            // Amounts recorded in another currency are converted into the account's currency.
            var amount = row.amount
            if let c = row.currency, c != source.currencyCode {
                amount = converter.convertOrSame(amount, from: c, to: source.currencyCode, on: row.date)
            }
            let sig = signature(date: row.date, kind: row.kind, amount: amount, account: source.name, note: row.note)
            if signatures.contains(sig) {
                result.skippedDuplicates += 1
                continue
            }

            let entry = LedgerEntry(
                kind: row.kind,
                amount: amount,
                currencyCode: source.currencyCode,
                date: row.date,
                note: row.note,
                account: source,
                category: category(named: row.category, kind: row.kind),
                tags: row.tags.map(tag(named:))
            )
            if let id = row.id { entry.id = id }
            if row.kind == .transfer, let toName = row.toAccount {
                let dest = account(named: toName, currency: row.toCurrency)
                entry.toAccount = dest
                if dest.currencyCode != source.currencyCode {
                    entry.toAmount = row.toAmount
                        ?? converter.convertOrSame(amount, from: source.currencyCode, to: dest.currencyCode, on: row.date)
                }
            }
            context.insert(entry)
            store.applySnapshot(to: entry, base: baseCurrency, converter: converter)
            knownIDs.insert(entry.id)
            signatures.insert(sig)
            result.imported += 1
        }
        try context.save()
        return result
    }

    private static func signature(_ e: LedgerEntry) -> String {
        signature(date: e.date, kind: e.kind, amount: e.amount, account: e.account?.name ?? "", note: e.note)
    }

    private static func signature(date: Date, kind: TransactionKind, amount: Decimal, account: String, note: String) -> String {
        let minute = Int(date.timeIntervalSince1970 / 60)
        return "\(minute)|\(kind.rawValue)|\(DecimalCodec.encode(amount))|\(account.lowercased())|\(note)"
    }
}
