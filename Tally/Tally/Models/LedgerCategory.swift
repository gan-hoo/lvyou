import Foundation
import SwiftData

/// An expense or income category with a user-customisable SF Symbol and colour.
@Model
final class LedgerCategory {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = CategoryKind.expense.rawValue
    var symbolName: String = "tag"
    var colorHex: String = "8E8E93"
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.category)
    var entries: [LedgerEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \Budget.category)
    var budgets: [Budget]? = []

    init(name: String, kind: CategoryKind, symbolName: String, colorHex: String, sortOrder: Int) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }
}

/// A free-form label that can be attached to many entries.
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "8E8E93"
    var isDemo: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.tags)
    var entries: [LedgerEntry]? = []

    init(name: String, colorHex: String = "8E8E93", isDemo: Bool = false) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.isDemo = isDemo
        self.createdAt = Date()
    }
}

/// A recurring monthly budget. `category == nil` means the overall budget.
@Model
final class Budget {
    var id: UUID = UUID()
    var amountRaw: String = "0"
    var currencyCode: String = "CNY"
    var category: LedgerCategory?
    /// Fraction of the budget (0.5…1.0) at which a gentle reminder appears.
    var alertThreshold: Double = 0.8
    var isDemo: Bool = false
    var createdAt: Date = Date()

    /// Set `category` after inserting the budget into a context.
    init(amount: Decimal, currencyCode: String, alertThreshold: Double = 0.8, isDemo: Bool = false) {
        self.id = UUID()
        self.amountRaw = DecimalCodec.encode(amount)
        self.currencyCode = currencyCode
        self.alertThreshold = alertThreshold
        self.isDemo = isDemo
        self.createdAt = Date()
    }

    var amount: Decimal {
        get { DecimalCodec.decode(amountRaw) }
        set { amountRaw = DecimalCodec.encode(newValue) }
    }

    var isOverall: Bool { category == nil }
}

/// One historical exchange rate: `1 baseCode = rate quoteCode`, effective from `effectiveDate`.
@Model
final class ExchangeRate {
    var id: UUID = UUID()
    var baseCode: String = "USD"
    var quoteCode: String = "CNY"
    var rateRaw: String = "1"
    var effectiveDate: Date = Date()
    var source: String = "manual"
    var createdAt: Date = Date()

    init(baseCode: String, quoteCode: String, rate: Decimal, effectiveDate: Date, source: String = "manual") {
        self.id = UUID()
        self.baseCode = baseCode
        self.quoteCode = quoteCode
        self.rateRaw = DecimalCodec.encode(rate)
        self.effectiveDate = Calendar.current.startOfDay(for: effectiveDate)
        self.source = source
        self.createdAt = Date()
    }

    var rate: Decimal {
        get { DecimalCodec.decode(rateRaw) }
        set { rateRaw = DecimalCodec.encode(newValue) }
    }

    enum Source {
        static let manual = "manual"
        static let online = "online"
        static let reference = "reference"
        static let imported = "import"
    }
}
