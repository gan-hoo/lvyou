import Foundation

/// 与时区相关的日期展示。所有方法都显式接收时区，
/// 保证记录按「打卡地当地时间」展示，而不是按设备当前时区。
enum CheckInDateFormatter {
    /// 例如「2026年11月7日，16:30」。
    static func dateTimeText(
        for date: Date,
        timeZone: TimeZone,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        dateText(for: date, timeZone: timeZone, locale: locale, calendar: calendar)
            + separator(locale: locale)
            + timeText(for: date, timeZone: timeZone, locale: locale, calendar: calendar)
    }

    /// 例如「2026年11月7日」。
    static func dateText(
        for date: Date,
        timeZone: TimeZone,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            Date.FormatStyle(date: .long, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone)
        )
    }

    /// 例如「16:30」。
    static func timeText(
        for date: Date,
        timeZone: TimeZone,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
        )
    }

    /// 例如「2026年11月」。
    static func monthTitle(
        for date: Date,
        timeZone: TimeZone,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).year().month(.wide)
        )
    }

    /// 打卡地当地的年、月、日。
    static func localComponents(for date: Date, timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    /// 例如「日本时间 · GMT+9」。
    static func timeZoneText(for timeZone: TimeZone, at date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        let offset = gmtOffsetText(secondsFromGMT: timeZone.secondsFromGMT(for: date))
        guard let name = timeZone.localizedName(for: .generic, locale: locale), !name.isEmpty else {
            return "\(timeZone.identifier) · \(offset)"
        }
        return "\(name) · \(offset)"
    }

    /// 例如「GMT+8」「GMT-3:30」「GMT」。
    static func gmtOffsetText(secondsFromGMT: Int) -> String {
        guard secondsFromGMT != 0 else { return "GMT" }
        let sign = secondsFromGMT > 0 ? "+" : "-"
        let total = abs(secondsFromGMT)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return minutes == 0
            ? "GMT\(sign)\(hours)"
            : String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }

    /// UTC ISO 8601 表示，例如「2026-11-07T08:30:00Z」。
    static func utcText(for date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func separator(locale: Locale) -> String {
        String(localized: "date.time.separator", defaultValue: "，", locale: locale, comment: "日期与时间之间的分隔符，如「2026年11月7日，16:30」")
    }
}
