import Foundation
import Testing
@testable import Tally

struct AmountExpressionTests {
    private func type(_ keys: String, digits: Int = 2) -> AmountExpression {
        var e = AmountExpression(maxFractionDigits: digits)
        for ch in keys {
            switch ch {
            case "0"..."9": e.input(digit: Int(String(ch))!)
            case ".": e.inputDecimalPoint()
            case "+": e.input(.plus)
            case "-": e.input(.minus)
            case "<": e.backspace()
            default: break
            }
        }
        return e
    }

    @Test func typesDigitsAndDecimals() {
        #expect(type("128.5").value == Decimal(string: "128.5"))
        #expect(type("128.5").expressionText == "128.5")
    }

    @Test func limitsFractionDigitsToCurrency() {
        #expect(type("9.999").value == Decimal(string: "9.99"))
        #expect(type("12.5", digits: 0).value == 125)
    }

    @Test func leadingZeroIsReplaced() {
        #expect(type("007").expressionText == "7")
        #expect(type(".5").expressionText == "0.5")
    }

    @Test func addsAndSubtractsWithDecimalPrecision() {
        // 0.1 + 0.2 must be exactly 0.3 (no binary floating point drift).
        #expect(type("0.1+0.2").value == Decimal(string: "0.3"))
        #expect(type("100-35.5+0.25").value == Decimal(string: "64.75"))
    }

    @Test func trailingOperatorIsIgnoredAndReplaceable() {
        let e = type("20+-")
        #expect(e.expressionText == "20−")
        #expect(e.value == 20)
        #expect(e.hasPendingOperation)
    }

    @Test func operatorWithoutNumberIsIgnored() {
        #expect(type("+").isEmpty)
    }

    @Test func backspaceRemovesCharactersThenOperators() {
        #expect(type("12+3<").expressionText == "12+")
        #expect(type("12+3<<").expressionText == "12")
        #expect(type("1<").isEmpty)
    }

    @Test func collapseReplacesExpressionWithResult() {
        var e = type("45+5.5")
        e.collapse()
        #expect(e.expressionText == "50.5")
        #expect(!e.hasPendingOperation)
    }

    @Test func editingStartsFromExistingValue() {
        let e = AmountExpression(value: Decimal(string: "88.80")!, maxFractionDigits: 2)
        #expect(e.expressionText == "88.8")
        #expect(e.value == Decimal(string: "88.8"))
    }

    @Test func capsIntegerDigits() {
        let e = type("123456789012345")
        #expect(e.expressionText.count == AmountExpression.maxIntegerDigits)
    }
}

struct DecimalCodecTests {
    @Test func roundTripsExactly() {
        for s in ["0", "0.1", "123456789.123456789", "-42.5", "0.000001"] {
            let d = Decimal(string: s)!
            #expect(DecimalCodec.decode(DecimalCodec.encode(d)) == d)
        }
    }

    @Test func parsesLenientInput() {
        #expect(DecimalCodec.parseLenient("1,234.50") == Decimal(string: "1234.5"))
        #expect(DecimalCodec.parseLenient("12,50") == Decimal(string: "12.5"))
        #expect(DecimalCodec.parseLenient("-¥32.10") == Decimal(string: "-32.1"))
        #expect(DecimalCodec.parseLenient("(45.00)") == Decimal(string: "-45"))
        #expect(DecimalCodec.parseLenient("1,234,567") == 1_234_567)
        #expect(DecimalCodec.parseLenient("abc") == nil)
        #expect(DecimalCodec.parseLenient("") == nil)
    }

    @Test func roundsHalfUp() {
        #expect(Decimal(string: "2.345")!.rounded(scale: 2) == Decimal(string: "2.35"))
        #expect(Decimal(string: "2.344")!.rounded(scale: 2) == Decimal(string: "2.34"))
    }

    /// Sums of converted amounts (including converted zeros) must compare equal to
    /// the same value written directly — split totals and net worth rely on it.
    @Test func roundedSumsCompareEqual() {
        let zero = (Decimal(0) * Decimal(string: "4.70")!).rounded(scale: 2)
        #expect(zero == 0)
        let parts: [Decimal] = [
            (Decimal(1_000) * 1).rounded(scale: 2),
            (Decimal(100) * Decimal(string: "4.70")!).rounded(scale: 2),
            zero,
        ]
        #expect(parts.sum { $0 } == 1_470)
        let splits = [Decimal(string: "33.33")!, Decimal(string: "66.67")!].map { $0.rounded(scale: 2) }
        #expect(splits.sum { $0 } == Decimal(100).rounded(scale: 2))
        #expect(Decimal(string: "1470.00")!.canonical == 1_470)
        // Same value, different internal forms: compare by value.
        #expect(Decimal(string: "1470.00")!.isSameAmount(as: 1_000 + 470))
        #expect(parts.sum { $0 }.isSameAmount(as: Decimal(1_000) + Decimal(470)))
        #expect(!Decimal(string: "1470.01")!.isSameAmount(as: 1_470))
    }
}

struct PeriodTests {
    @Test func monthBoundaries() {
        var c = DateComponents(); c.year = 2024; c.month = 2; c.day = 15; c.hour = 13
        let date = Calendar.current.date(from: c)!
        let p = Period.month(date)
        #expect(p.dayCount == 29) // leap year
        #expect(p.contains(date))
        #expect(!p.contains(p.end))
        #expect(p.next.start == p.end)
        #expect(p.previous.end == p.start)
    }

    @Test func yearHasTwelveMonths() {
        let p = Period.year(.now)
        #expect(p.months.count == 12)
        #expect(p.months.first?.start == p.start)
    }
}

struct ComparablePeriodTests {
    @Test func inProgressMonthComparesSameSpanOfPreviousMonth() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10))!
        let november = Period.month(now)
        let october = november.previous
        let end = november.comparableEnd(in: october, now: now)
        #expect(cal.component(.day, from: end) == 12)
        #expect(cal.component(.month, from: end) == 10)
        // A finished period compares against the whole previous period.
        #expect(october.comparableEnd(in: october.previous, now: now) == october.previous.end)
    }
}
