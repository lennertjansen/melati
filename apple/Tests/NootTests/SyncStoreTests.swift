import XCTest
@preconcurrency import SQLiteDB

final class SyncStoreTests: XCTestCase {
    private var dbPath: String!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("noot-sync-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("journal.db").path
    }

    override func tearDown() {
        if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
        super.tearDown()
    }

    private func makeStore() throws -> JournalStore {
        try JournalStore(path: dbPath, key: randomKey())
    }

    private func randomKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private let fields = Data("fake-system-fields".utf8)

    // MARK: migration + adoption

    func testMigrationV3AdoptsExistingEntriesAsPending() async throws {
        let key = randomKey()
        // v2-shaped DB with one entry, no sync tables.
        do {
            let db = try Connection(dbPath)
            let hex = key.map { String(format: "%02x", $0) }.joined()
            try db.execute("PRAGMA key = \"x'\(hex)'\"")
            try db.execute("""
                CREATE TABLE entries (
                    date TEXT PRIMARY KEY, content TEXT NOT NULL,
                    created_at TEXT, location TEXT, modified_at TEXT
                ) WITHOUT ROWID;
            """)
            try db.run(
                "INSERT INTO entries VALUES (?, ?, ?, ?, ?)",
                "2026-07-01", "pre-sync entry", nil as String?, nil as String?, "2026-07-01T10:00:00.000Z"
            )
            try db.execute("PRAGMA user_version = 2")
        }

        let store = try JournalStore(path: dbPath, key: key)
        let row = try await store.syncRow(date: "2026-07-01")
        XCTAssertEqual(row?.pending, true, "pre-sync entries must adopt as pending")
        XCTAssertNil(row?.systemFields)
        let pending = try await store.pendingDates()
        XCTAssertEqual(pending, ["2026-07-01"])
    }

    // MARK: put() marks pending + emits

    func testPutMarksPendingAndEmitsChange() async throws {
        let store = try makeStore()
        let stream = await store.localChanges
        try await store.put(JournalEntry(date: "2026-08-04", content: "x", createdAt: nil, location: nil))

        var iterator = stream.makeAsyncIterator()
        let change = await iterator.next()
        XCTAssertEqual(change, .entryChanged(date: "2026-08-04"))

        let row = try await store.syncRow(date: "2026-08-04")
        XCTAssertEqual(row?.pending, true)
        let actual1 = try await store.pendingDates()
        XCTAssertEqual(actual1, ["2026-08-04"])
    }

    // MARK: putFromSync

    func testPutFromSyncOverwritesEverythingAndClearsPending() async throws {
        let store = try makeStore()
        try await store.put(JournalEntry(date: "2026-08-04", content: "local", createdAt: Date(), location: "Amsterdam"))

        try await store.putFromSync(
            date: "2026-08-04",
            content: "remote",
            createdAt: "2026-08-04T08:00:00.000Z",
            location: "Paris",
            modifiedAt: "2026-08-04T09:00:00.123Z",
            systemFields: fields,
            backupReason: "lww-remote-won"
        )

        let entry = try await store.get(date: "2026-08-04")
        XCTAssertEqual(entry?.content, "remote")
        XCTAssertEqual(entry?.location, "Paris")

        let row = try await store.syncRow(date: "2026-08-04")
        XCTAssertEqual(row?.pending, false)
        XCTAssertEqual(row?.lastSyncedModifiedAt, "2026-08-04T09:00:00.123Z")
        XCTAssertEqual(row?.systemFields, fields)
        let actual2 = try await store.pendingDates()
        XCTAssertEqual(actual2, [], "remote-applied entry must not need upload")

        let backups = try await store.conflictBackups(for: "2026-08-04")
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups[0].content, "local", "the overwritten local row must be preserved")
        XCTAssertEqual(backups[0].reason, "lww-remote-won")
    }

    func testPutFromSyncWithoutBackupReasonKeepsBackupsEmpty() async throws {
        let store = try makeStore()
        try await store.putFromSync(
            date: "2026-08-05", content: "fresh", createdAt: nil, location: nil,
            modifiedAt: "2026-08-05T10:00:00.000Z", systemFields: fields
        )
        let actual3 = try await store.conflictBackups(for: "2026-08-05")
        XCTAssertEqual(actual3, [])
        let actual4 = try await store.get(date: "2026-08-05")?.content
        XCTAssertEqual(actual4, "fresh")
    }

    // MARK: markUploaded in-flight guard

    func testMarkUploadedClearsPendingWhenNothingChanged() async throws {
        let store = try makeStore()
        try await store.put(JournalEntry(date: "2026-08-04", content: "v1", createdAt: nil, location: nil))
        let fetched = try await store.get(date: "2026-08-04")
        let stamp = isoString(try XCTUnwrap(fetched?.modifiedAt))

        try await store.markUploaded(date: "2026-08-04", uploadedModifiedAt: stamp, systemFields: fields)

        let row = try await store.syncRow(date: "2026-08-04")
        XCTAssertEqual(row?.pending, false)
        XCTAssertEqual(row?.lastSyncedModifiedAt, stamp)
        let actual5 = try await store.pendingDates()
        XCTAssertEqual(actual5, [])
    }

    func testMarkUploadedKeepsPendingWhenEditedDuringFlight() async throws {
        let store = try makeStore()
        try await store.put(JournalEntry(date: "2026-08-04", content: "v1", createdAt: nil, location: nil))
        let fetched = try await store.get(date: "2026-08-04")
        let uploadedStamp = isoString(try XCTUnwrap(fetched?.modifiedAt))

        // Edit lands while the upload is "in flight".
        try await store.put(JournalEntry(date: "2026-08-04", content: "v2", createdAt: nil, location: nil))

        try await store.markUploaded(date: "2026-08-04", uploadedModifiedAt: uploadedStamp, systemFields: fields)

        let row = try await store.syncRow(date: "2026-08-04")
        XCTAssertEqual(row?.pending, true, "newer local edit must stay dirty")
        let actual6 = try await store.pendingDates()
        XCTAssertEqual(actual6, ["2026-08-04"])
    }

    func testRapidPutsGetStrictlyIncreasingStamps() async throws {
        // Sub-millisecond consecutive edits must never share a stamp -
        // equal stamps defeat the in-flight guard and LWW ordering.
        let store = try makeStore()
        var stamps: [Date] = []
        for i in 0..<5 {
            try await store.put(JournalEntry(date: "2026-08-04", content: "v\(i)", createdAt: nil, location: nil))
            let entry = try await store.get(date: "2026-08-04")
            stamps.append(try XCTUnwrap(entry?.modifiedAt))
        }
        for i in 1..<stamps.count {
            XCTAssertGreaterThan(stamps[i], stamps[i - 1],
                                 "stamp \(i) must be strictly greater than its predecessor")
        }
    }

    func testNoOpSaveDoesNotBumpClockOrMarkPending() async throws {
        // UI saves on every blur/tab-flip. If a content-identical save bumped
        // modified_at, the device with the entry on screen would always win
        // LWW and remote edits could never land (two-device test finding).
        let store = try makeStore()
        try await store.put(JournalEntry(date: "2026-08-04", content: "text", createdAt: nil, location: "Amsterdam"))
        let fetched = try await store.get(date: "2026-08-04")
        let stamp = isoString(try XCTUnwrap(fetched?.modifiedAt))
        try await store.markUploaded(date: "2026-08-04", uploadedModifiedAt: stamp, systemFields: fields)

        // Identical save: must be a complete no-op.
        try await store.put(JournalEntry(date: "2026-08-04", content: "text", createdAt: nil, location: "Amsterdam"))

        let after = try await store.get(date: "2026-08-04")
        XCTAssertEqual(after?.modifiedAt.map(isoString), stamp, "no-op save must not bump the LWW clock")
        let row = try await store.syncRow(date: "2026-08-04")
        XCTAssertEqual(row?.pending, false, "no-op save must not re-mark pending")
        let pendingAfter = try await store.pendingDates()
        XCTAssertEqual(pendingAfter, [])

        // A REAL change still writes.
        try await store.put(JournalEntry(date: "2026-08-04", content: "text v2", createdAt: nil, location: "Amsterdam"))
        let changed = try await store.get(date: "2026-08-04")
        XCTAssertNotEqual(changed?.modifiedAt.map(isoString), stamp)
        let pendingChanged = try await store.pendingDates()
        XCTAssertEqual(pendingChanged, ["2026-08-04"])
    }

    // MARK: healing invariant

    func testPendingDatesHealsLostPendingFlag() async throws {
        let store = try makeStore()
        try await store.put(JournalEntry(date: "2026-08-04", content: "v1", createdAt: nil, location: nil))
        let fetched = try await store.get(date: "2026-08-04")
        let stamp = isoString(try XCTUnwrap(fetched?.modifiedAt))
        try await store.markUploaded(date: "2026-08-04", uploadedModifiedAt: stamp, systemFields: fields)
        let actual7 = try await store.pendingDates()
        XCTAssertEqual(actual7, [])

        // Simulate the crash case: entry data changed but pending flag lost.
        // storeSystemFields sets pending only via INSERT path; an edit changes
        // modified_at - even if pending were somehow 0, the mismatch heals it.
        try await store.put(JournalEntry(date: "2026-08-04", content: "v2", createdAt: nil, location: nil))
        let healed = try await store.pendingDates()
        XCTAssertEqual(healed, ["2026-08-04"],
                       "modified_at != last_synced must surface as pending regardless of flag")
    }

    // MARK: deleteFromSync

    func testDeleteFromSyncRemovesAndBacksUp() async throws {
        let store = try makeStore()
        try await store.put(JournalEntry(date: "2026-08-04", content: "precious", createdAt: nil, location: nil))
        try await store.deleteFromSync(date: "2026-08-04")

        let actual8 = try await store.get(date: "2026-08-04")
        XCTAssertNil(actual8)
        let actual9 = try await store.syncRow(date: "2026-08-04")
        XCTAssertNil(actual9)
        let backups = try await store.conflictBackups(for: "2026-08-04")
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups[0].content, "precious")
        XCTAssertEqual(backups[0].reason, "remote-delete")
    }

    // MARK: resetSyncState

    func testResetSyncStateKeepsDataMarksAllPending() async throws {
        let store = try makeStore()
        try await store.put(JournalEntry(date: "2026-08-01", content: "a", createdAt: nil, location: nil))
        let fetched = try await store.get(date: "2026-08-01")
        let stamp = isoString(try XCTUnwrap(fetched?.modifiedAt))
        try await store.markUploaded(date: "2026-08-01", uploadedModifiedAt: stamp, systemFields: fields)
        try await store.setSyncMeta(key: "engine_state", value: Data("state".utf8))

        try await store.resetSyncState()

        let actual10 = try await store.get(date: "2026-08-01")?.content
        XCTAssertEqual(actual10, "a", "data survives")
        let row = try await store.syncRow(date: "2026-08-01")
        XCTAssertEqual(row?.pending, true)
        XCTAssertNil(row?.systemFields)
        XCTAssertNil(row?.lastSyncedModifiedAt)
        let actual11 = try await store.syncMeta(key: "engine_state")
        XCTAssertNil(actual11)
        let actual12 = try await store.pendingDates()
        XCTAssertEqual(actual12, ["2026-08-01"])
    }

    // MARK: sync_meta round trip

    func testSyncMetaRoundTrip() async throws {
        let store = try makeStore()
        let actual13 = try await store.syncMeta(key: "engine_state")
        XCTAssertNil(actual13)
        try await store.setSyncMeta(key: "engine_state", value: Data([1, 2, 3]))
        let actual14 = try await store.syncMeta(key: "engine_state")
        XCTAssertEqual(actual14, Data([1, 2, 3]))
        try await store.setSyncMeta(key: "engine_state", value: nil)
        let actual15 = try await store.syncMeta(key: "engine_state")
        XCTAssertNil(actual15)
    }

    private func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
