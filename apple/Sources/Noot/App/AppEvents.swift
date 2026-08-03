import Foundation

// Shared between the macOS and iOS shells: tab identity + app-wide events.

enum NavTab: Hashable, CaseIterable {
    case today, entries, calendar

    var labelKey: LocalizedStringResource {
        switch self {
        case .today: return "tab.today"
        case .entries: return "tab.entries"
        case .calendar: return "tab.calendar"
        }
    }
}

extension Notification.Name {
    static let nootNewEntry = Notification.Name("NootNewEntry")
    static let nootSelectTab = Notification.Name("NootSelectTab")
    static let nootFocusLocation = Notification.Name("NootFocusLocation")
}
