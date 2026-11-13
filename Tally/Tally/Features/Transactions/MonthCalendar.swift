import SwiftUI

/// Month grid for the Transactions tab: each day shows what was spent (or earned),
/// tinted by how large the day was. Tapping a day narrows the list to that day.
struct MonthCalendar: View {
    let month: Period
    /// Day totals for the month, from the same filtered entries as the list.
    let groups: [DayGroup]
    let base: String
    @Binding var selected: Date?

    private var calendar: Calendar { .ledger }

    private struct Cell: Identifiable {
        let id: Int
        let day: Date?
    }

    private var totals: [Date: DayGroup] {
        Dictionary(groups.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var cells: [Cell] {
        let first = month.start
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var result = (0..<leading).map { Cell(id: -1 - $0, day: nil) }
        for (i, day) in month.days.enumerated() {
            result.append(Cell(id: i, day: day))
        }
        return result
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var largestExpense: Decimal {
        groups.map(\.expense).max() ?? 0
    }

    var body: some View {
        let totals = totals
        let largest = largestExpense
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(cells) { cell in
                    if let day = cell.day {
                        DayCell(
                            day: day,
                            group: totals[day],
                            largest: largest,
                            base: base,
                            isSelected: selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                        ) {
                            Haptics.selection()
                            withMotion(DS.Motion.snappy) {
                                if let current = selected, calendar.isDate(current, inSameDayAs: day) {
                                    selected = nil
                                } else {
                                    selected = day
                                }
                            }
                        }
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
        }
        .card(padding: DS.Spacing.m)
    }
}

private struct DayCell: View {
    let day: Date
    let group: DayGroup?
    let largest: Decimal
    let base: String
    let isSelected: Bool
    var onTap: () -> Void

    private var calendar: Calendar { .ledger }
    private var isToday: Bool { calendar.isDateInToday(day) }
    private var isFuture: Bool { day > .now }
    private var expense: Decimal { group?.expense ?? 0 }
    private var income: Decimal { group?.income ?? 0 }

    /// 0…1: how this day's spending compares with the biggest day of the month.
    private var intensity: Double {
        guard largest > 0, expense > 0 else { return 0 }
        return min(1, (expense / largest).doubleValue)
    }

    private var amountText: String? {
        if expense > 0 { return "-" + MoneyFormat.compact(expense.doubleValue) }
        if income > 0 { return "+" + MoneyFormat.compact(income.doubleValue) }
        return nil
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(verbatim: String(calendar.component(.day, from: day)))
                    .font(.subheadline.weight(isToday || isSelected ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white : (isToday ? DS.Colors.accent : Color.primary))
                Group {
                    if let amountText, !AppSettings.hideAmounts {
                        Text(verbatim: amountText)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.9)
                                             : (expense > 0 ? Color.secondary : DS.Colors.income))
                    } else if group != nil {
                        Circle().fill(isSelected ? Color.white : DS.Colors.accent).frame(width: 4, height: 4)
                    } else {
                        Text(verbatim: " ")
                    }
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DS.Colors.accent.opacity(0.6), lineWidth: 1)
                }
            }
            .opacity(isFuture && group == nil ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: day.text(.dateTime.month(.wide).day().weekday(.wide))))
        .accessibilityValue(Text(verbatim: accessibilityAmount))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return DS.Colors.accent }
        if intensity > 0 { return DS.Colors.accent.opacity(0.06 + 0.26 * intensity) }
        return Color.clear
    }

    private var accessibilityAmount: String {
        var parts: [String] = []
        if expense > 0 { parts.append(String(localized: "Expenses") + " " + MoneyFormat.string(expense, code: base)) }
        if income > 0 { parts.append(String(localized: "Income") + " " + MoneyFormat.string(income, code: base)) }
        return parts.joined(separator: ", ")
    }
}

/// Shown above the list while one calendar day is selected.
struct SelectedDayBar: View {
    let day: Date
    var onShowMonth: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "calendar").foregroundStyle(DS.Colors.accent)
            Text(verbatim: day.text(.dateTime.month(.abbreviated).day().weekday(.abbreviated)))
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Show Whole Month", action: onShowMonth)
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, DS.Spacing.s)
    }
}
