import Foundation
import SwiftData
import Testing
@testable import Tally

struct CSVCodecTests {
    @Test func parsesQuotedFieldsAndNewlines() {
        let text = "\u{FEFF}a,b,c\r\n1,\"hello, world\",\"say \"\"hi\"\"\"\n2,\"multi\nline\",\n"
        let rows = CSVCodec.parse(text)
        #expect(rows.count == 3)
        #expect(rows[0] == ["a", "b", "c"])
        #expect(rows[1] == ["1", "hello, world", "say \"hi\""])
        #expect(rows[2] == ["2", "multi\nline", ""])
    }

    @Test func serializeEscapesWhenNeeded() {
        let out = CSVCodec.serialize([["plain", "with,comma", "quote\"d"]])
        #expect(out == "plain,\"with,comma\",\"quote\"\"d\"\r\n")
        #expect(CSVCodec.parse(out) == [["plain", "with,comma", "quote\"d"]])
    }

    @Test func detectsKindsFromWordsAndSigns() {
        #expect(LedgerCSVImporter.parseKind("支出", signedAmount: 5) == .expense)
        #expect(LedgerCSVImporter.parseKind("Income", signedAmount: 5) == .income)
        #expect(LedgerCSVImporter.parseKind("转账", signedAmount: 5) == .transfer)
        #expect(LedgerCSVImporter.parseKind("", signedAmount: -5) == .expense)
        #expect(LedgerCSVImporter.parseKind("", signedAmount: 5) == .income)
    }

    @Test func previewRecognisesChineseHeaders() throws {
        let csv = """
        日期,类型,金额,账户,分类,备注,标签
        2025-03-01 12:30,支出,32.5,现金,餐饮,午饭,工作;午餐
        2025/03/02,收入,"1,000.00",银行卡,工资,,
        not a date,支出,1,现金,餐饮,,
        2025-03-03,支出,abc,现金,餐饮,,
        """
        let preview = try LedgerCSVImporter.preview(text: csv)
        #expect(preview.rows.count == 2)
        #expect(preview.issues.map(\.line) == [4, 5])
        let first = try #require(preview.rows.first)
        #expect(first.kind == .expense)
        #expect(first.amount == Decimal(string: "32.5"))
        #expect(first.account == "现金")
        #expect(first.category == "餐饮")
        #expect(first.tags == ["工作", "午餐"])
        #expect(preview.rows[1].amount == 1000)
    }

    @Test func missingRequiredColumnsThrows() {
        #expect(throws: (any Error).self) {
            _ = try LedgerCSVImporter.preview(text: "Note,Category\nfoo,bar\n")
        }
    }
}

@MainActor
struct CSVRoundTripTests {
    @Test func exportThenImportIsLosslessAndIdempotent() throws {
        let source = try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = source.mainContext
        let service = TransactionService(context: ctx)
        let food = LedgerCategory(name: "Food", kind: .expense, symbolName: "fork.knife", colorHex: "F2994A", sortOrder: 0)
        let pets = LedgerCategory(name: "Pets", kind: .expense, symbolName: "pawprint", colorHex: "D98E5F", sortOrder: 1)
        let cash = Account(name: "Cash, Wallet", kind: .cash, currencyCode: "CNY")
        let aud = Account(name: "AUD", kind: .debitCard, currencyCode: "AUD")
        ctx.insert(food); ctx.insert(pets); ctx.insert(cash); ctx.insert(aud)
        ctx.insert(ExchangeRate(baseCode: "AUD", quoteCode: "CNY", rate: 5, effectiveDate: .distantPast))
        try ctx.save()

        var expense = TransactionDraft(kind: .expense, amount: Decimal(string: "12.34")!, date: .now,
                                       note: "Note with \"quotes\", commas\nand newline", account: cash, category: food)
        expense.payee = "Market"
        try service.save(expense, baseCurrency: "CNY")
        var split = TransactionDraft(kind: .expense, amount: 10, date: .now, account: cash)
        split.splits = [SplitDraft(category: food, amount: 6), SplitDraft(category: pets, amount: 4)]
        try service.save(split, baseCurrency: "CNY")
        var transfer = TransactionDraft(kind: .transfer, amount: 500, date: .now, account: cash, toAccount: aud)
        transfer.fee = 2
        try service.save(transfer, baseCurrency: "CNY")

        let csv = LedgerCSVExporter.csvString(for: try ctx.fetch(FetchDescriptor<LedgerEntry>()))

        let target = try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let tctx = target.mainContext
        tctx.insert(ExchangeRate(baseCode: "AUD", quoteCode: "CNY", rate: 5, effectiveDate: .distantPast))
        let preview = try LedgerCSVImporter.preview(text: csv)
        #expect(preview.issues.isEmpty)
        let result = try LedgerCSVImporter.apply(preview, context: tctx, baseCurrency: "CNY")
        #expect(result.imported == 3)
        #expect(result.createdAccounts == 2)
        #expect(result.failed.isEmpty)

        let imported = try tctx.fetch(FetchDescriptor<LedgerEntry>())
        let plain = try #require(imported.first { $0.kind == .expense && !$0.isSplit })
        #expect(plain.amount == Decimal(string: "12.34"))
        #expect(plain.note == "Note with \"quotes\", commas\nand newline")
        #expect(plain.payee == "Market")
        #expect(plain.account?.name == "Cash, Wallet")
        let splitBack = try #require(imported.first { $0.isSplit })
        #expect(splitBack.splitList.map(\.amount) == [6, 4])
        let transferBack = try #require(imported.first { $0.kind == .transfer })
        #expect(transferBack.toAccount?.currencyCode == "AUD")
        #expect(transferBack.toAmount == 100)
        #expect(transferBack.fee == 2)

        let again = try LedgerCSVImporter.apply(try LedgerCSVImporter.preview(text: csv), context: tctx, baseCurrency: "CNY")
        #expect(again.imported == 0)
        #expect(again.skippedDuplicates == 3)
    }

    @Test func foreignRowsWithoutRateAreReportedNotGuessed() throws {
        let container = try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        ctx.insert(Account(name: "Cash", kind: .cash, currencyCode: "CNY"))
        try ctx.save()
        let csv = "Date,Amount,Currency,Account\n2025-03-01,10,USD,Cash\n"
        let result = try LedgerCSVImporter.apply(try LedgerCSVImporter.preview(text: csv), context: ctx, baseCurrency: "CNY")
        #expect(result.imported == 0)
        #expect(result.failed.count == 1)
    }
}
