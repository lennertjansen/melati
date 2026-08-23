import XCTest

/// Pins the prev/next stepping contract shared by both shells (the UI-test
/// coverage for this lives in the local-only MelatiUITests scheme, so these
/// hostless tests are what CI actually runs).
final class EntryNavigationTests: XCTestCase {
    func testTodayInsertedWhenRowless() {
        let nav = EntryNavigation(
            entryDates: ["2026-08-18", "2026-08-15"], todayKey: "2026-08-21")
        XCTAssertEqual(nav.dates, ["2026-08-21", "2026-08-18", "2026-08-15"])
    }

    func testTodayNotDuplicatedWhenItHasARow() {
        let nav = EntryNavigation(
            entryDates: ["2026-08-21", "2026-08-15"], todayKey: "2026-08-21")
        XCTAssertEqual(nav.dates, ["2026-08-21", "2026-08-15"])
    }

    func testSteppingSkipsDateGaps() {
        let nav = EntryNavigation(
            entryDates: ["2026-08-18", "2026-08-13", "2026-07-02"], todayKey: "2026-08-21")
        XCTAssertEqual(nav.older(than: "2026-08-21"), "2026-08-18")
        XCTAssertEqual(nav.older(than: "2026-08-13"), "2026-07-02")
        XCTAssertEqual(nav.newer(than: "2026-07-02"), "2026-08-13")
        XCTAssertEqual(nav.newer(than: "2026-08-18"), "2026-08-21")
    }

    func testEndsReturnNil() {
        let nav = EntryNavigation(
            entryDates: ["2026-08-18", "2026-08-15"], todayKey: "2026-08-21")
        XCTAssertNil(nav.newer(than: "2026-08-21"))
        XCTAssertNil(nav.older(than: "2026-08-15"))
    }

    func testUnknownDateReturnsNil() {
        let nav = EntryNavigation(entryDates: ["2026-08-18"], todayKey: "2026-08-21")
        XCTAssertNil(nav.older(than: "2026-08-19"))
        XCTAssertNil(nav.newer(than: "2026-08-19"))
    }

    func testRowlessTodayWithNoEntriesStandsAlone() {
        let nav = EntryNavigation(entryDates: [], todayKey: "2026-08-21")
        XCTAssertEqual(nav.dates, ["2026-08-21"])
        XCTAssertNil(nav.older(than: "2026-08-21"))
        XCTAssertNil(nav.newer(than: "2026-08-21"))
    }

    func testTodayInsertedInOrderAmongNewerEntries() {
        // Future-dated entries can exist after a device clock skew; the sort
        // must keep the list strictly newest-first regardless.
        let nav = EntryNavigation(
            entryDates: ["2026-08-22", "2026-08-19"], todayKey: "2026-08-21")
        XCTAssertEqual(nav.dates, ["2026-08-22", "2026-08-21", "2026-08-19"])
    }
}
