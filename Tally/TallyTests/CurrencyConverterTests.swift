import Foundation
import Testing
@testable import Tally

struct CurrencyConverterTests {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    @Test func usesRateEffectiveOnTheDate() {
        let c = CurrencyConverter(points: [
            RatePoint(base: "AUD", quote: "CNY", rate: dec("4.60"), date: day(2025, 1, 1)),
            RatePoint(base: "AUD", quote: "CNY", rate: dec("4.80"), date: day(2025, 6, 1)),
        ])
        #expect(c.rate(from: "AUD", to: "CNY", on: day(2025, 3, 15)) == dec("4.60"))
        #expect(c.rate(from: "AUD", to: "CNY", on: day(2025, 6, 1)) == dec("4.80"))
        #expect(c.rate(from: "AUD", to: "CNY", on: day(2026, 1, 1)) == dec("4.80"))
        // Before any rate exists, the earliest known rate is used.
        #expect(c.rate(from: "AUD", to: "CNY", on: day(2020, 1, 1)) == dec("4.60"))
    }

    @Test func invertsReverseRates() throws {
        let c = CurrencyConverter(points: [RatePoint(base: "USD", quote: "CNY", rate: dec("8"), date: day(2025, 1, 1))])
        let r = try #require(c.rate(from: "CNY", to: "USD", on: day(2025, 2, 1)))
        #expect(r == dec("0.125"))
    }

    @Test func crossesThroughPivotCurrency() throws {
        let c = CurrencyConverter(points: [
            RatePoint(base: "USD", quote: "CNY", rate: dec("7"), date: day(2025, 1, 1)),
            RatePoint(base: "USD", quote: "AUD", rate: dec("1.4"), date: day(2025, 1, 1)),
        ])
        let r = try #require(c.rate(from: "AUD", to: "CNY", on: day(2025, 2, 1)))
        #expect(r == dec("5"))
        #expect(c.convert(100, from: "AUD", to: "CNY", on: day(2025, 2, 1)) == 500)
    }

    @Test func sameCurrencyIsIdentityAndUnknownIsNil() {
        let c = CurrencyConverter(points: [])
        #expect(c.rate(from: "JPY", to: "JPY") == 1)
        #expect(c.rate(from: "JPY", to: "CNY") == nil)
        #expect(c.convertOrSame(10, from: "JPY", to: "CNY") == 10)
    }

    @Test func roundsToTargetCurrencyDigits() {
        let c = CurrencyConverter(points: [RatePoint(base: "USD", quote: "JPY", rate: dec("153.27"), date: day(2025, 1, 1))])
        #expect(c.convert(dec("9.99"), from: "USD", to: "JPY", on: day(2025, 1, 2)) == 1531)
    }

    @Test func prefersTheMostRecentOfDirectAndInverse() {
        let c = CurrencyConverter(points: [
            RatePoint(base: "USD", quote: "CNY", rate: dec("7"), date: day(2025, 1, 1)),
            RatePoint(base: "CNY", quote: "USD", rate: dec("0.125"), date: day(2025, 5, 1)),
        ])
        #expect(c.rate(from: "USD", to: "CNY", on: day(2025, 3, 1)) == dec("7"))
        #expect(c.rate(from: "USD", to: "CNY", on: day(2025, 6, 1)) == dec("8"))
    }
}
