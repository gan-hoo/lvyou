import Foundation

/// Ledger entry kinds. See docs/FINANCE_RULES.md for how each affects balances and reports.
enum TransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense
    case income
    case transfer
    case refund
    case adjustment

    var id: String { rawValue }

    /// Kinds offered by the quick-entry switcher.
    static let primary: [TransactionKind] = [.expense, .income, .transfer]

    var title: String {
        switch self {
        case .expense: String(localized: "Expense")
        case .income: String(localized: "Income")
        case .transfer: String(localized: "Transfer")
        case .refund: String(localized: "Refund")
        case .adjustment: String(localized: "Balance Adjustment")
        }
    }

    var symbol: String {
        switch self {
        case .expense: "arrow.up.right"
        case .income: "arrow.down.left"
        case .transfer: "arrow.left.arrow.right"
        case .refund: "arrow.uturn.backward"
        case .adjustment: "slider.horizontal.3"
        }
    }

    /// Category kind used by this transaction kind.
    var categoryKind: CategoryKind? {
        switch self {
        case .expense, .refund: .expense
        case .income: .income
        case .transfer, .adjustment: nil
        }
    }
}

enum CategoryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense
    case income

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: String(localized: "Expense")
        case .income: String(localized: "Income")
        }
    }

    var transactionKind: TransactionKind {
        switch self {
        case .expense: .expense
        case .income: .income
        }
    }
}

enum AccountKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cash
    case debitCard
    case savings
    case eWallet
    case multiCurrency
    case investment
    case otherAsset
    case creditCard
    case loan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: String(localized: "Cash")
        case .debitCard: String(localized: "Debit Card")
        case .savings: String(localized: "Savings")
        case .eWallet: String(localized: "E-Wallet")
        case .multiCurrency: String(localized: "Multi-currency")
        case .investment: String(localized: "Investment")
        case .otherAsset: String(localized: "Other Asset")
        case .creditCard: String(localized: "Credit Card")
        case .loan: String(localized: "Debt")
        }
    }

    var defaultSymbol: String {
        switch self {
        case .cash: "banknote"
        case .debitCard: "creditcard"
        case .savings: "building.columns"
        case .eWallet: "iphone.gen3"
        case .multiCurrency: "globe"
        case .investment: "chart.line.uptrend.xyaxis"
        case .otherAsset: "shippingbox"
        case .creditCard: "creditcard.and.123"
        case .loan: "doc.text"
        }
    }

    /// Credit cards and debts normally carry a negative balance (money owed).
    var isLiability: Bool { self == .creditCard || self == .loan }

    var sortRank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum BudgetAlertLevel: Int, Comparable, Sendable {
    case normal = 0
    case approaching = 1
    case exceeded = 2

    static func < (lhs: BudgetAlertLevel, rhs: BudgetAlertLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum BudgetPeriodKind: String, CaseIterable, Identifiable, Sendable {
    case monthly
    case weekly
    case yearly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: String(localized: "Monthly")
        case .weekly: String(localized: "Weekly")
        case .yearly: String(localized: "Yearly")
        case .custom: String(localized: "Custom")
        }
    }
}

enum RecurrenceFrequency: String, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: String(localized: "Daily")
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        case .yearly: String(localized: "Yearly")
        }
    }

    var component: Calendar.Component {
        switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }
}
