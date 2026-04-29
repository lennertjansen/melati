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
}
