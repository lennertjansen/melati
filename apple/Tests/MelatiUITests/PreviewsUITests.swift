import XCTest

/// Regression coverage for the previews privacy mode: previews (entry body
/// AND location) are opt-in and default OFF on every surface. Same isolated-DB
/// seam and local-only constraints as NavigationUITests.
@MainActor
final class PreviewsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var dbDir: String!

    private var today = ""
    private var seeded: [String] = []

    override func setUp() async throws {
        continueAfterFailure = false

        // The toggle persists in the app's real preferences domain; remove it
        // so every test starts from the true "missing preference" state.
        Self.deletePreviewsPref()

        let base = NSHomeDirectory()
            + "/Library/Containers/com.lennertjansen.melati/Data/tmp"
        dbDir = base + "/melati-previews-e2e-" + UUID().uuidString

        today = Self.dateKey(daysAgo: 0)
        seeded = [1, 3].map { Self.dateKey(daysAgo: $0) }

        try FileManager.default.createDirectory(
            atPath: dbDir, withIntermediateDirectories: true)
        let store = try JournalStore(
            path: dbDir + "/journal.db", key: AppEnvironment.testModeKey)
        for date in seeded {
            try await store.put(JournalEntry(
                date: date,
                content: "Seed entry for \(date).",
                createdAt: Date(),
                location: "Seedville"
            ))
        }

        app = XCUIApplication()
        app.launchEnvironment["MELATI_TEST_DB_DIR"] = dbDir
        app.launch()
    }

    override func tearDown() {
        app?.terminate()
        if let dbDir { try? FileManager.default.removeItem(atPath: dbDir) }
        Self.deletePreviewsPref()
    }

    /// Missing preference means OFF: no entry body and no location readable
    /// on the calendar or the entries list (both groupings).
    func testDefaultHidesBodyAndLocationEverywhere() {
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(calCell().waitForExistence(timeout: 3))
        XCTAssertFalse(exposesSeedContent(calCell()), "calendar leaked with previews off")

        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(entriesRow().waitForExistence(timeout: 3))
        XCTAssertFalse(exposesSeedContent(entriesRow()), "entries (flat) leaked with previews off")

        // Grouped list renders through a different code path.
        app.radioButtons.element(boundBy: 1).click()
        XCTAssertTrue(entriesRow().waitForExistence(timeout: 3))
        XCTAssertFalse(exposesSeedContent(entriesRow()), "entries (grouped) leaked with previews off")
        app.radioButtons.element(boundBy: 0).click()
    }

    /// The eye button turns previews on for BOTH surfaces (body AND location);
    /// Shift-Cmd-P turns them back off.
    func testEyeAndMenuShortcutGateBothSurfaces() {
        app.typeKey("3", modifierFlags: .command)
        let eye = app.buttons["cal.previews"]
        XCTAssertTrue(eye.waitForExistence(timeout: 3))
        eye.click()

        XCTAssertTrue(waitUntil { self.exposesSeedContent(self.calCell()) },
                      "calendar previews missing after eye toggle")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(waitUntil { self.exposesSeedContent(self.entriesRow()) },
                      "entries preview missing after eye toggle")
        XCTAssertTrue(value(of: entriesRow()).contains("Seedville"),
                      "entries location missing after eye toggle")

        app.typeKey("p", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitUntil { !self.exposesSeedContent(self.entriesRow()) },
                      "entries still leaked after shortcut off")
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(waitUntil { !self.exposesSeedContent(self.calCell()) },
                      "calendar still leaked after shortcut off")
    }

    /// The choice persists across relaunch.
    func testToggledOnPersistsAcrossRelaunch() {
        app.typeKey("3", modifierFlags: .command)
        let eye = app.buttons["cal.previews"]
        XCTAssertTrue(eye.waitForExistence(timeout: 3))
        eye.click()
        XCTAssertTrue(waitUntil { self.exposesSeedContent(self.calCell()) })

        app.terminate()
        app.launch()
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(calCell().waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntil { self.exposesSeedContent(self.calCell()) },
                      "previews-on did not survive relaunch")
    }

    // MARK: - Helpers

    // Child Texts of these Buttons are flattened by macOS AX and dropped from
    // the derived label, so the app mirrors visible preview content into each
    // button's accessibilityValue (also fixing VoiceOver). Assertions read
    // that value on the SPECIFIC seeded cell/row - app-wide text queries over
    // the whole AX tree time out on the webview subtree.
    private func calCell() -> XCUIElement { app.buttons["cal.day.\(seeded[0])"] }
    private func entriesRow() -> XCUIElement { app.buttons["entries.row.\(seeded[0])"] }

    private func value(of element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }

    private func exposesSeedContent(_ element: XCUIElement) -> Bool {
        let v = value(of: element)
        return v.contains("Seed entry for") || v.contains("Seedville")
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    /// The app is sandboxed, so its defaults live in its container; the
    /// `defaults` CLI follows that redirection (raw CFPreferences from this
    /// unsandboxed runner would write the wrong plist).
    private static func deletePreviewsPref() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["delete", "com.lennertjansen.melati", "melati.showPreviews"]
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    private static func dateKey(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
