import Foundation

/// RFC 4180 CSV reading and writing (quoted fields, escaped quotes, CRLF, BOM).
enum CSVCodec {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text.unicodeScalars)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field); field = ""
                case "\r":
                    break
                case "\n":
                    row.append(field); field = ""
                    rows.append(row); row = []
                default:
                    field.unicodeScalars.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }

    private static let specialCharacters: Set<Character> = [",", "\"", "\n", "\r", "\r\n"]

    static func escape(_ field: String) -> String {
        if field.contains(where: { specialCharacters.contains($0) }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func serialize(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}

/// Column layout of Tally's CSV export (also the preferred import layout).
enum LedgerCSVColumn: String, CaseIterable {
    case date = "Date"
    case type = "Type"
    case amount = "Amount"
    case currency = "Currency"
    case account = "Account"
    case toAccount = "To Account"
    case toAmount = "To Amount"
    case toCurrency = "To Currency"
    case category = "Category"
    case splits = "Splits"
    case payee = "Payee"
    case fee = "Fee"
    case discount = "Discount"
    case tags = "Tags"
    case note = "Note"
    case baseCurrency = "Base Currency"
    case rateToBase = "Rate To Base"
    case baseAmount = "Base Amount"
    case id = "ID"

    /// Header aliases accepted on import (English and Chinese, case-insensitive).
    var aliases: [String] {
        switch self {
        case .date: ["date", "time", "datetime", "日期", "时间", "交易时间", "记账时间"]
        case .type: ["type", "kind", "类型", "收支类型", "交易类型"]
        case .amount: ["amount", "value", "金额", "数额"]
        case .currency: ["currency", "币种", "货币"]
        case .account: ["account", "from account", "账户", "付款账户", "转出账户"]
        case .toAccount: ["to account", "transfer to", "转入账户", "收款账户"]
        case .toAmount: ["to amount", "转入金额"]
        case .toCurrency: ["to currency", "转入币种"]
        case .category: ["category", "分类", "类别"]
        case .splits: ["splits", "拆分"]
        case .payee: ["payee", "merchant", "商家", "交易对象", "对方"]
        case .fee: ["fee", "手续费", "手續費"]
        case .discount: ["discount", "折扣", "优惠", "優惠", "优惠金额"]
        case .tags: ["tags", "tag", "标签"]
        case .note: ["note", "notes", "memo", "description", "备注", "说明"]
        case .baseCurrency: ["base currency", "本位币"]
        case .rateToBase: ["rate to base", "汇率"]
        case .baseAmount: ["base amount", "本位币金额"]
        case .id: ["id", "uuid"]
        }
    }
}

enum CSVDate {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static let exportFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    private static let patterns = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
        "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd",
        "yyyy.MM.dd", "yyyy年M月d日 HH:mm", "yyyy年M月d日",
        "dd/MM/yyyy HH:mm", "dd/MM/yyyy", "MM/dd/yyyy",
    ]

    private static let formatters: [DateFormatter] = patterns.map { p in
        let f = DateFormatter()
        f.locale = posix
        f.timeZone = .current
        f.dateFormat = p
        return f
    }

    static func parse(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        for f in formatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
