import XCTest
@preconcurrency import SQLiteDB

final class JournalStoreTests: XCTestCase {
    private var dbPath: String!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("melati-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("journal.db").path
    }

    override func tearDown() {
        if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
        super.tearDown()
    }

    func testRoundTripEncryptDecrypt() async throws {
        let key = randomKey()
        let store = try JournalStore(path: dbPath, key: key)
        let entry = JournalEntry(
            date: "2026-04-29",
            content: "# Hello\nFirst entry.",
            createdAt: Date(timeIntervalSince1970: 1714000000),
            location: "Amsterdam"
        )
        try await store.put(entry)
        let loaded = try await store.get(date: "2026-04-29")
        XCTAssertEqual(loaded?.date, entry.date)
        XCTAssertEqual(loaded?.content, entry.content)
        XCTAssertEqual(loaded?.location, entry.location)
        XCTAssertNotNil(loaded?.createdAt)
    }

    func testFileEncryptedAtRest() async throws {
        let key = randomKey()
        let store = try JournalStore(path: dbPath, key: key)
        try await store.put(JournalEntry(
            date: "2026-04-29",
            content: "secret thoughts",
            createdAt: nil,
            location: nil
        ))
        // Force a checkpoint by reopening (closes the store).
        _ = store
        let header = try Data(contentsOf: URL(fileURLWithPath: dbPath)).prefix(16)
        let asString = String(data: Data(header), encoding: .ascii) ?? ""
        XCTAssertFalse(asString.hasPrefix("SQLite format 3"),
                       "DB file leaks 'SQLite format 3' header — encryption is not applied.")
        let raw = try Data(contentsOf: URL(fileURLWithPath: dbPath))
        XCTAssertFalse(raw.range(of: Data("secret thoughts".utf8)) != nil,
                       "Plaintext content found in DB file on disk.")
    }

    func testWrongKeyFails() async throws {
        let keyA = randomKey()
        let keyB = randomKey()
        let store = try JournalStore(path: dbPath, key: keyA)
        try await store.put(JournalEntry(
            date: "2026-04-29",
            content: "data",
            createdAt: nil,
            location: nil
        ))
        // Drop the first store, re-open with a different key — must throw.
        _ = store
        XCTAssertThrowsError(try JournalStore(path: dbPath, key: keyB)) { error in
            XCTAssertTrue(error is JournalStoreError, "Expected JournalStoreError, got \(error)")
        }
    }

    func testListDatesOrderingDesc() async throws {
        let key = randomKey()
        let store = try JournalStore(path: dbPath, key: key)
        for date in ["2026-04-27", "2026-04-29", "2026-04-28"] {
            try await store.put(JournalEntry(date: date, content: "x", createdAt: nil, location: nil))
        }
        let dates = try await store.listDates()
        XCTAssertEqual(dates, ["2026-04-29", "2026-04-28", "2026-04-27"])
    }

    func testExtractPreviewStripsMarkdown() {
        XCTAssertEqual(EntryUtil.extractPreview(from: "# Heading\nbody"), "Heading")
        XCTAssertEqual(EntryUtil.extractPreview(from: "- item one\n- two"), "item one")
        XCTAssertEqual(EntryUtil.extractPreview(from: "**bold** word"), "bold word")
        XCTAssertEqual(EntryUtil.extractPreview(from: "`code` here"), "code here")
        XCTAssertEqual(EntryUtil.extractPreview(from: "\n\nlater line"), "later line")
        XCTAssertEqual(EntryUtil.extractPreview(from: ""), "")
    }

    func testPutStampsModifiedAt() async throws {
        let key = randomKey()
        let store = try JournalStore(path: dbPath, key: key)
        let before = Date().addingTimeInterval(-1)
        try await store.put(JournalEntry(date: "2026-08-03", content: "v1", createdAt: nil, location: nil))
        let first = try await store.get(date: "2026-08-03")
        let firstStamp = try XCTUnwrap(first?.modifiedAt)
        XCTAssertGreaterThan(firstStamp, before, "modified_at must be stamped at write time")

        try await store.put(JournalEntry(date: "2026-08-03", content: "v2", createdAt: nil, location: nil))
        let second = try await store.get(date: "2026-08-03")
        let secondStamp = try XCTUnwrap(second?.modifiedAt)
        XCTAssertGreaterThanOrEqual(secondStamp, firstStamp, "every put() must bump modified_at")
    }

    func testMigrationV1ToV2BackfillsModifiedAt() async throws {
        let key = randomKey()
        // Build a v1-shaped DB by hand (no modified_at column), then reopen
        // through JournalStore and assert the migration ran.
        do {
            let db = try Connection(dbPath)
            let hex = key.map { String(format: "%02x", $0) }.joined()
            try db.execute("PRAGMA key = \"x'\(hex)'\"")
            try db.execute("""
                CREATE TABLE entries (
                    date TEXT PRIMARY KEY,
                    content TEXT NOT NULL,
                    created_at TEXT,
                    location TEXT
                ) WITHOUT ROWID;
            """)
            try db.run(
                "INSERT INTO entries (date, content, created_at, location) VALUES (?, ?, ?, ?)",
                "2026-05-01", "with created_at", "2026-05-01T09:30:00.000Z", nil as String?
            )
            try db.run(
                "INSERT INTO entries (date, content, created_at, location) VALUES (?, ?, ?, ?)",
                "2026-05-02", "without created_at", nil as String?, nil as String?
            )
            try db.execute("PRAGMA user_version = 1")
        }

        let store = try JournalStore(path: dbPath, key: key)
        let withCreated = try await store.get(date: "2026-05-01")
        XCTAssertEqual(withCreated?.modifiedAt, withCreated?.createdAt,
                       "backfill must copy created_at into modified_at")
        let withoutCreated = try await store.get(date: "2026-05-02")
        XCTAssertNotNil(withoutCreated?.modifiedAt,
                        "backfill must synthesize midnight stamp when created_at is null")
    }

    private func randomKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}

final class KeyStoreTests: XCTestCase {
    private var keyStore: KeyStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if os(iOS)
        // Hostless iOS test bundles get no keychain entitlement (-34018);
        // macOS covers this code path in CI, and iOS keychain behavior was
        // verified on hardware (C1: persistence through force-quit).
        throw XCTSkip("keychain unavailable in hostless iOS test bundle")
        #endif
        keyStore = KeyStore(
            service: "com.lennertjansen.melati.tests",
            account: "test-key-\(UUID().uuidString)"
        )
    }

    override func tearDown() {
        keyStore?.deleteAll()
        super.tearDown()
    }

    func testLoadOrCreateGeneratesKey() throws {
        let key = try keyStore.loadOrCreate()
        XCTAssertEqual(key.count, 32, "Key must be 256 bits")
    }

    func testLoadOrCreateIsStable() throws {
        let key1 = try keyStore.loadOrCreate()
        let key2 = try keyStore.loadOrCreate()
        XCTAssertEqual(key1, key2, "Second load must return the same key")
    }
}
