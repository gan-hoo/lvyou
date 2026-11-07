import Testing
import Foundation
@testable import TravelFootprints

struct CheckInDateFormatterTests {
    let locale = Locale(identifier: "zh_Hans_CN")
    let calendar = Calendar(identifier: .gregorian)

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier))
    }

    @Test func formatsInCheckInTimeZone() throws {
        let instant = try date("2026-11-07T08:30:00Z")
        let text = CheckInDateFormatter.dateTimeText(
            for: instant, timeZone: try zone("Asia/Shanghai"), locale: locale, calendar: calendar
        )
        #expect(text == "2026年11月7日，16:30")
    }

    @Test func sameInstantDiffersAcrossTimeZones() throws {
        // 同一时刻：东京已是 11 月 8 日清晨，洛杉矶仍是 11 月 7 日中午。
        let instant = try date("2026-11-07T20:00:00Z")
        let tokyo = try zone("Asia/Tokyo")
        let losAngeles = try zone("America/Los_Angeles")

        #expect(CheckInDateFormatter.dateText(for: instant, timeZone: tokyo, locale: locale, calendar: calendar) == "2026年11月8日")
        #expect(CheckInDateFormatter.dateText(for: instant, timeZone: losAngeles, locale: locale, calendar: calendar) == "2026年11月7日")

        let tokyoParts = CheckInDateFormatter.localComponents(for: instant, timeZone: tokyo)
        let laParts = CheckInDateFormatter.localComponents(for: instant, timeZone: losAngeles)
        #expect(tokyoParts.day == 8 && tokyoParts.hour == 5 && tokyoParts.minute == 0)
        #expect(laParts.day == 7 && laParts.hour == 12 && laParts.minute == 0)

        // 完整文本以日期开头、以本地化时间结尾。
        let text = CheckInDateFormatter.dateTimeText(for: instant, timeZone: tokyo, locale: locale, calendar: calendar)
        #expect(text.hasPrefix("2026年11月8日，"))
        #expect(text.hasSuffix(CheckInDateFormatter.timeText(for: instant, timeZone: tokyo, locale: locale, calendar: calendar)))
    }

    @Test func localYearUsesCheckInTimeZone() throws {
        // UTC 仍是 2026 年最后一天，东京已是 2027 年元旦。
        let instant = try date("2026-12-31T20:00:00Z")
        #expect(CheckInDateFormatter.localComponents(for: instant, timeZone: try zone("Asia/Tokyo")).year == 2027)
        #expect(CheckInDateFormatter.localComponents(for: instant, timeZone: try zone("UTC")).year == 2026)
    }

    @Test func gmtOffsetText() {
        #expect(CheckInDateFormatter.gmtOffsetText(secondsFromGMT: 0) == "GMT")
        #expect(CheckInDateFormatter.gmtOffsetText(secondsFromGMT: 8 * 3600) == "GMT+8")
        #expect(CheckInDateFormatter.gmtOffsetText(secondsFromGMT: -8 * 3600) == "GMT-8")
        #expect(CheckInDateFormatter.gmtOffsetText(secondsFromGMT: 5 * 3600 + 1800) == "GMT+5:30")
        #expect(CheckInDateFormatter.gmtOffsetText(secondsFromGMT: -(3 * 3600 + 1800)) == "GMT-3:30")
    }

    @Test func utcTextIsISO8601() throws {
        let instant = try date("2026-11-07T08:30:00Z")
        #expect(CheckInDateFormatter.utcText(for: instant) == "2026-11-07T08:30:00Z")
    }

    @Test @MainActor func checkInStoresTimeZoneAndOffset() throws {
        let container = TestFixtures.makeContainer()
        let instant = try date("2026-11-07T08:30:00Z")
        let checkIn = CheckIn(visitedAt: instant, timeZone: try zone("Asia/Tokyo"), method: .gpsVerified)
        container.mainContext.insert(checkIn)
        #expect(checkIn.timeZoneIdentifier == "Asia/Tokyo")
        #expect(checkIn.utcOffsetSeconds == 9 * 3600)
        #expect(checkIn.timeZone.identifier == "Asia/Tokyo")
    }
}
