import Foundation

/// Calculator-style amount input supporting `+` and `−`, evaluated with `Decimal`.
struct AmountExpression: Equatable {
    enum Operator: String, Equatable {
        case plus = "+"
        case minus = "−"
    }

    enum Token: Equatable {
        case number(String)
        case op(Operator)
    }

    private(set) var tokens: [Token] = []
    var maxFractionDigits: Int = 2
    static let maxIntegerDigits = 10

    init(maxFractionDigits: Int = 2) {
        self.maxFractionDigits = maxFractionDigits
    }

    /// Starts from an existing amount (when editing).
    init(value: Decimal, maxFractionDigits: Int = 2) {
        self.maxFractionDigits = maxFractionDigits
        if value > 0 {
            tokens = [.number(Self.trimmed(DecimalCodec.encode(value.rounded(scale: maxFractionDigits))))]
        }
    }

    var isEmpty: Bool { tokens.isEmpty }

    var hasPendingOperation: Bool {
        tokens.contains { if case .op = $0 { return true } else { return false } }
            && tokens.count > 1
    }

    // MARK: Input

    mutating func input(digit: Int) {
        guard (0...9).contains(digit) else { return }
        let d = String(digit)
        if case .number(let current)? = tokens.last {
            if current == "0" {
                replaceLast(.number(d))
                return
            }
            if let dot = current.firstIndex(of: ".") {
                let fraction = current.distance(from: dot, to: current.endIndex) - 1
                guard fraction < maxFractionDigits else { return }
            } else {
                guard current.count < Self.maxIntegerDigits else { return }
            }
            replaceLast(.number(current + d))
        } else {
            tokens.append(.number(d))
        }
    }

    mutating func inputDecimalPoint() {
        guard maxFractionDigits > 0 else { return }
        if case .number(let current)? = tokens.last {
            guard !current.contains(".") else { return }
            replaceLast(.number(current + "."))
        } else {
            tokens.append(.number("0."))
        }
    }

    mutating func input(_ op: Operator) {
        switch tokens.last {
        case .none:
            return
        case .op?:
            replaceLast(.op(op))
        case .number?:
            tokens.append(.op(op))
        }
    }

    mutating func backspace() {
        guard let last = tokens.last else { return }
        switch last {
        case .op:
            tokens.removeLast()
        case .number(let s):
            let shorter = String(s.dropLast())
            if shorter.isEmpty || shorter == "-" {
                tokens.removeLast()
            } else {
                replaceLast(.number(shorter))
            }
        }
    }

    mutating func clear() { tokens.removeAll() }

    /// Replaces the expression with its evaluated result.
    mutating func collapse() {
        let result = value
        tokens = result == 0 ? [] : [.number(Self.trimmed(DecimalCodec.encode(result)))]
    }

    // MARK: Output

    /// Evaluated value; a trailing operator is ignored.
    var value: Decimal {
        var result: Decimal = 0
        var pending: Operator = .plus
        for token in tokens {
            switch token {
            case .number(let s):
                let n = Decimal(string: s.hasSuffix(".") ? String(s.dropLast()) : s, locale: Locale(identifier: "en_US_POSIX")) ?? 0
                result = pending == .plus ? result + n : result - n
            case .op(let op):
                pending = op
            }
        }
        return result.rounded(scale: maxFractionDigits)
    }

    /// Raw expression for display, e.g. "120+35.5−8".
    var expressionText: String {
        tokens.map {
            switch $0 {
            case .number(let s): s
            case .op(let op): op.rawValue
            }
        }.joined()
    }

    private mutating func replaceLast(_ token: Token) {
        tokens[tokens.count - 1] = token
    }

    private static func trimmed(_ s: String) -> String {
        guard s.contains(".") else { return s }
        var t = s
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t
    }
}
