import Foundation
import SwiftUI

/// The three kinds of ledger entries.
enum TransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense
    case income
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: String(localized: "Expense")
        case .income: String(localized: "Income")
        case .transfer: String(localized: "Transfer")
        }
    }

    var symbol: String {
        switch self {
        case .expense: "arrow.up.right"
        case .income: "arrow.down.left"
        case .transfer: "arrow.left.arrow.right"
        }
    }

    /// Category kind used by this transaction kind (transfers have no category).
    var categoryKind: CategoryKind? {
        switch self {
        case .expense: .expense
        case .income: .income
        case .transfer: nil
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
    case creditCard
    case savings
    case eWallet
    case investment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: String(localized: "Cash")
        case .debitCard: String(localized: "Debit Card")
        case .creditCard: String(localized: "Credit Card")
        case .savings: String(localized: "Savings")
        case .eWallet: String(localized: "E-Wallet")
        case .investment: String(localized: "Investment")
        }
    }

    var defaultSymbol: String {
        switch self {
        case .cash: "banknote"
        case .debitCard: "creditcard"
        case .creditCard: "creditcard.and.123"
        case .savings: "building.columns"
        case .eWallet: "iphone.gen3"
        case .investment: "chart.line.uptrend.xyaxis"
        }
    }

    /// Credit cards usually carry a negative balance (a liability).
    var isLiability: Bool { self == .creditCard }
}

enum BudgetAlertLevel: Int, Comparable, Sendable {
    case normal = 0
    case approaching = 1
    case exceeded = 2

    static func < (lhs: BudgetAlertLevel, rhs: BudgetAlertLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
