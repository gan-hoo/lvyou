import Foundation

/// 时间线中的一个月份分组（以打卡地当地日期划分）。
struct TimelineSection: Identifiable {
    /// year * 100 + month，例如 202611。
    let id: Int
    let title: String
    let checkIns: [CheckIn]

    static func make(from checkIns: [CheckIn], locale: Locale = .autoupdatingCurrent) -> [TimelineSection] {
        let valid = checkIns.filter { !$0.isDeleted }
        let grouped = Dictionary(grouping: valid) { checkIn -> Int in
            let components = CheckInDateFormatter.localComponents(for: checkIn.visitedAt, timeZone: checkIn.timeZone)
            return (components.year ?? 0) * 100 + (components.month ?? 0)
        }
        return grouped
            .map { key, items in
                let sorted = items.sorted { $0.visitedAt > $1.visitedAt }
                let first = sorted[0]
                return TimelineSection(
                    id: key,
                    title: CheckInDateFormatter.monthTitle(for: first.visitedAt, timeZone: first.timeZone, locale: locale),
                    checkIns: sorted
                )
            }
            .sorted { $0.id > $1.id }
    }
}
