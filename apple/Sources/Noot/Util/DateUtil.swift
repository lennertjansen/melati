import Foundation

enum DateUtil {
    struct HeaderParts: Equatable, Sendable {
        let dayName: String
        let dateText: String
        let timeText: String
    }

    static func todayKey() -> String {
        toDateKey(Date())
    }

    static func toDateKey(_ date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func parseDateKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Calendar.current.date(from: components)
    }

    static func formatHeaderParts(dateKey: String, createdAt: Date?) -> HeaderParts {
        let date = parseDateKey(dateKey) ?? Date()

        let dayFmt = DateFormatter()
        dayFmt.locale = .current
        dayFmt.setLocalizedDateFormatFromTemplate("EEEE")

        let dateFmt = DateFormatter()
        dateFmt.locale = .current
        dateFmt.dateStyle = .long

        let timeFmt = DateFormatter()
        timeFmt.locale = .current
        timeFmt.timeStyle = .short

        return HeaderParts(
            dayName: dayFmt.string(from: date),
            dateText: dateFmt.string(from: date),
            timeText: timeFmt.string(from: createdAt ?? Date())
        )
    }

    static func formatRelativeDate(dateKey: String) -> String {
        if dateKey == todayKey() {
            return String(localized: "relative.today")
        }
        let cal = Calendar.current
        if let yesterday = cal.date(byAdding: .day, value: -1, to: Date()),
           dateKey == toDateKey(yesterday) {
            return String(localized: "relative.yesterday")
        }
        guard let date = parseDateKey(dateKey) else { return dateKey }
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.setLocalizedDateFormatFromTemplate("EEEE MMMM d, yyyy")
        return fmt.string(from: date)
    }

    struct MonthDay: Identifiable, Equatable {
        let date: Date
        let dateKey: String
        let isCurrentMonth: Bool
        var id: String { dateKey }
    }

    static func getMonthDays(year: Int, month: Int) -> [MonthDay] {
        let cal = Calendar.current
        let firstWeekday = cal.firstWeekday
        var firstOfMonthComponents = DateComponents()
        firstOfMonthComponents.year = year
        firstOfMonthComponents.month = month
        firstOfMonthComponents.day = 1
        guard let firstOfMonth = cal.date(from: firstOfMonthComponents) else { return [] }

        let firstDayWeekday = cal.component(.weekday, from: firstOfMonth)
        let startOffset = (firstDayWeekday - firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -startOffset, to: firstOfMonth) else { return [] }

        var days: [MonthDay] = []
        for i in 0..<42 {
            guard let d = cal.date(byAdding: .day, value: i, to: gridStart) else { continue }
            let monthComponent = cal.component(.month, from: d)
            days.append(MonthDay(
                date: d,
                dateKey: toDateKey(d),
                isCurrentMonth: monthComponent == month
            ))
        }
        return days
    }

    static func formatMonthYear(year: Int, month: Int) -> String {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return "" }
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return fmt.string(from: date)
    }

    struct WeekdayLabel: Identifiable, Equatable {
        let dayOfWeek: Int
        let label: String
        var id: Int { dayOfWeek }
    }

    static func getWeekdayLabels() -> [WeekdayLabel] {
        let cal = Calendar.current
        let firstDay = cal.firstWeekday  // 1 = Sunday
        let fmt = DateFormatter()
        fmt.locale = .current
        let narrow = fmt.veryShortStandaloneWeekdaySymbols ?? []
        var labels: [WeekdayLabel] = []
        for i in 0..<7 {
            let weekday = ((firstDay - 1) + i) % 7  // 0..6 (0 = Sunday)
            let label = weekday < narrow.count ? narrow[weekday] : ""
            labels.append(WeekdayLabel(dayOfWeek: weekday, label: label))
        }
        return labels
    }
}
