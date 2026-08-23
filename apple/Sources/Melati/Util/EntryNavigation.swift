import Foundation

/// Positional prev/next stepping over the dates reachable from an open entry:
/// every entry plus today, which is always openable and editable even before
/// it has a row. Newest-first, matching the store's date-DESC order. Stepping
/// is by position, not by calendar, so gaps between entry dates are skipped.
/// Shared by both shells; unit-tested in EntryNavigationTests.
struct EntryNavigation {
    let dates: [String]

    /// - Parameter entryDates: existing entry dates, newest-first
    ///   (`JournalStore.listDates()` order).
    init(entryDates: [String], todayKey: String) {
        if entryDates.contains(todayKey) {
            dates = entryDates
        } else {
            dates = ([todayKey] + entryDates).sorted(by: >)
        }
    }

    func older(than date: String) -> String? {
        guard let idx = dates.firstIndex(of: date), idx + 1 < dates.count else { return nil }
        return dates[idx + 1]
    }

    func newer(than date: String) -> String? {
        guard let idx = dates.firstIndex(of: date), idx > 0 else { return nil }
        return dates[idx - 1]
    }
}
