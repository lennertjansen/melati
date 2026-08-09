import XCTest

/// E2E navigation tests driving the real Mac app on an isolated database
/// (MELATI_TEST_DB_DIR seam). The real diary and keychain are never touched.
/// Local-only: launching the app needs signing, so this scheme stays off CI.
///
/// Written to assert CORRECT behavior - running them against broken code is
/// the bug reproduction, running them after the fix is the proof.
@MainActor
final class NavigationUITests: XCTestCase {
    private var app: XCUIApplication!
    private var dbDir: String!

    private var today = ""
    /// Non-adjacent seeded dates, oldest last (2, 5, 8 days ago + today).
    private var seededPast: [String] = []

    override func setUp() async throws {
        continueAfterFailure = false

        // Must live inside the app's sandbox container or the sandboxed app
        // cannot open it.
        let base = NSHomeDirectory()
            + "/Library/Containers/com.lennertjansen.melati/Data/tmp"
        dbDir = base + "/melati-e2e-" + UUID().uuidString

        today = Self.dateKey(daysAgo: 0)
        seededPast = [2, 5, 8].map { Self.dateKey(daysAgo: $0) }

        // Seed through the same store code the app uses, with the shared
        // test-mode key. The store closes when it goes out of scope here,
        // before the app launches - never two writers.
        try FileManager.default.createDirectory(
            atPath: dbDir, withIntermediateDirectories: true)
        let store = try JournalStore(
            path: dbDir + "/journal.db", key: AppEnvironment.testModeKey)
        for date in [today] + seededPast {
            try await store.put(JournalEntry(
                date: date,
                content: "Seed entry \(date)",
                createdAt: Date(),
                location: nil
            ))
        }

        app = XCUIApplication()
        app.launchEnvironment["MELATI_TEST_DB_DIR"] = dbDir
        app.launch()
    }

    override func tearDown() {
        app?.terminate()
        if let dbDir { try? FileManager.default.removeItem(atPath: dbDir) }
    }

    // MARK: - Bug 1: no way back from a calendar-opened entry

    /// The back chevron must actually dismiss the entry. Pre-fix the pointer
    /// travelling to it crosses the sidebar hover strip, the sidebar slides
    /// over the chevron, and the click lands on the sidebar instead.
    func testBackChevronDismissesCalendarOpenedEntry() {
        openCalendarCell(seededPast[1])
        assertDetailShown(seededPast[1])

        app.buttons["entry.back"].click()
        // Opened from the calendar, so leaving returns there.
        XCTAssertTrue(element("cal.day.\(today)").waitForExistence(timeout: 3),
                      "back chevron did not dismiss the entry")
    }

    /// Clicking the CURRENT tab in the sidebar must also leave the detail
    /// view. Pre-fix it was a no-op (selection unchanged -> onChange never
    /// fired -> selectedDate never cleared) and the user was stuck.
    func testSidebarCurrentTabClickLeavesDetail() {
        openCalendarCell(seededPast[1])
        assertDetailShown(seededPast[1])

        // Hover the left edge to summon the sidebar, like a user would.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).hover()
        let calRow = app.buttons["sidebar.calendar"]
        XCTAssertTrue(calRow.waitForExistence(timeout: 2), "sidebar did not appear on edge hover")
        calRow.click()

        XCTAssertTrue(element("cal.day.\(today)").waitForExistence(timeout: 3),
                      "clicking the current tab in the sidebar left the user stuck on the entry")
    }

    // MARK: - Bug 2: today opened from Entries/Calendar must be editable

    func testTodayOpenedFromEntriesIsEditable() {
        app.typeKey("2", modifierFlags: .command)
        let row = app.buttons["entries.row.\(today)"]
        XCTAssertTrue(row.waitForExistence(timeout: 3), "today's row missing from Entries")
        row.click()

        XCTAssertTrue(element("editor.editable").waitForExistence(timeout: 3),
                      "today via Entries must open the editable Today surface")

        // Prove it E2E: type and see the text land in the editor.
        let editor = app.webViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click()
        editor.typeText("Remote e2e typing works")
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@",
                            "Remote e2e typing works", "Remote e2e typing works")
            ).firstMatch.waitForExistence(timeout: 3),
            "typed text never appeared - today's entry is not editable"
        )
    }

    func testTodayOpenedFromCalendarIsEditable() {
        openCalendarCell(today)
        XCTAssertTrue(element("editor.editable").waitForExistence(timeout: 3),
                      "today via Calendar must open the editable Today surface")
    }

    // MARK: - Bug 3: flipping through non-adjacent entries

    /// Visible chevrons must exist on Mac and must skip date gaps (the
    /// seeded entries are 3 days apart).
    func testChevronsFlipAcrossDateGaps() {
        app.typeKey("2", modifierFlags: .command)
        let row = app.buttons["entries.row.\(seededPast[1])"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        assertDetailShown(seededPast[1])

        let older = app.buttons["entry.older"]
        XCTAssertTrue(older.waitForExistence(timeout: 3),
                      "no older-entry chevron on Mac")
        older.click()
        assertDetailShown(seededPast[2])

        let newer = app.buttons["entry.newer"]
        XCTAssertTrue(newer.waitForExistence(timeout: 3),
                      "no newer-entry chevron on Mac")
        newer.click()
        assertDetailShown(seededPast[1])
        newer.click()
        assertDetailShown(seededPast[0])

        // Newest hop lands on today, which must be the EDITABLE surface.
        newer.click()
        XCTAssertTrue(element("editor.editable").waitForExistence(timeout: 3),
                      "flipping to today must land on the editable Today surface")
    }

    /// Today opened from the calendar BEFORE anything was written that day
    /// has no DB row; prev/next must still work (positional, not index-based).
    func testFlippingFromRowlessToday() async throws {
        // Re-launch with a DB that has past entries but nothing for today.
        app.terminate()
        try FileManager.default.removeItem(atPath: dbDir)
        try FileManager.default.createDirectory(atPath: dbDir, withIntermediateDirectories: true)
        let store = try JournalStore(
            path: dbDir + "/journal.db", key: AppEnvironment.testModeKey)
        for date in seededPast {
            try await store.put(JournalEntry(
                date: date, content: "Seed entry \(date)",
                createdAt: Date(), location: nil))
        }
        app.launch()

        openCalendarCell(today)
        XCTAssertTrue(element("editor.editable").waitForExistence(timeout: 3))

        let older = app.buttons["entry.older"]
        XCTAssertTrue(older.waitForExistence(timeout: 3),
                      "older chevron missing on a day with no entry yet")
        older.click()
        assertDetailShown(seededPast[0])
    }

    // MARK: - Helpers

    private static func dateKey(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Opens a date cell in the calendar, paging back up to 2 months for
    /// seeds that fall across a month boundary.
    private func openCalendarCell(_ dateKey: String) {
        app.typeKey("3", modifierFlags: .command)
        let cell = app.buttons["cal.day.\(dateKey)"]
        var pagesBack = 0
        while !cell.waitForExistence(timeout: 2), pagesBack < 2 {
            app.buttons["cal.prevMonth"].click()
            pagesBack += 1
        }
        XCTAssertTrue(cell.exists, "calendar cell \(dateKey) not found")
        cell.click()
    }

    /// SwiftUI containers surface as different AX element types per OS
    /// version; match by identifier across all types.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// A read-only past entry for `dateKey` is on screen.
    private func assertDetailShown(_ dateKey: String) {
        XCTAssertTrue(
            element("entry.header.\(dateKey)").waitForExistence(timeout: 3),
            "entry \(dateKey) did not open"
        )
        XCTAssertTrue(element("editor.readonly").exists,
                      "entry \(dateKey) opened but is not the read-only surface")
    }
}
