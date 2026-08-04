import Foundation
@preconcurrency import SQLiteDB

enum JournalStoreError: Error {
    case wrongKey
}

actor JournalStore {
    private let db: Connection
    private var changeContinuations: [UUID: AsyncStream<LocalChange>.Continuation] = [:]
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(path: String, key: Data) throws {
        let db = try Connection(path)
        try Self.applyKey(db, key: key)
        try Self.runMigrations(db)
        self.db = db
    }

    static func defaultDatabaseURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appendingPathComponent("journal.db")
    }

    private static func applyKey(_ db: Connection, key: Data) throws {
        let hex = key.map { String(format: "%02x", $0) }.joined()
        try db.execute("PRAGMA key = \"x'\(hex)'\"")
        do {
            _ = try db.scalar("SELECT count(*) FROM sqlite_master")
        } catch {
            throw JournalStoreError.wrongKey
        }
    }

    private static func runMigrations(_ db: Connection) throws {
        let version = (try? db.scalar("PRAGMA user_version") as? Int64) ?? 0
        if version < 1 {
            try db.execute("""
                CREATE TABLE IF NOT EXISTS entries (
                    date TEXT PRIMARY KEY,
                    content TEXT NOT NULL,
                    created_at TEXT,
                    location TEXT
                ) WITHOUT ROWID;
            """)
            try db.execute("PRAGMA user_version = 1")
        }
        if version < 2 {
            // Sync prerequisite: last-writer-wins needs a per-entry modification
            // clock. ISO8601 with fractional seconds sorts lexicographically ==
            // chronologically, so string comparison is safe.
            try db.execute("ALTER TABLE entries ADD COLUMN modified_at TEXT")
            try db.execute("UPDATE entries SET modified_at = COALESCE(created_at, date || 'T00:00:00.000Z')")
            try db.execute("PRAGMA user_version = 2")
        }
        if version < 3 {
            // Sync bookkeeping. Lives inside the SQLCipher DB on purpose:
            // engine state and data state get backed up/encrypted/deleted
            // together and can never diverge.
            try db.execute("""
                CREATE TABLE IF NOT EXISTS sync_state (
                    date TEXT PRIMARY KEY,
                    system_fields BLOB,
                    last_synced_modified_at TEXT,
                    pending INTEGER NOT NULL DEFAULT 1
                ) WITHOUT ROWID;
            """)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS sync_meta (
                    key TEXT PRIMARY KEY,
                    value BLOB
                ) WITHOUT ROWID;
            """)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS conflict_backups (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    date TEXT NOT NULL,
                    content TEXT NOT NULL,
                    location TEXT,
                    modified_at TEXT,
                    backed_up_at TEXT NOT NULL,
                    reason TEXT
                );
            """)
            // Adoption: everything already written locally is dirty and will
            // upload on first sync.
            try db.execute("INSERT OR IGNORE INTO sync_state (date, pending) SELECT date, 1 FROM entries")
            try db.execute("PRAGMA user_version = 3")
        }
    }

    func get(date: String) throws -> JournalEntry? {
        let stmt = try db.prepare("SELECT date, content, created_at, location, modified_at FROM entries WHERE date = ?")
        for row in try stmt.run(date) {
            return JournalEntry(
                date: row[0] as? String ?? "",
                content: row[1] as? String ?? "",
                createdAt: (row[2] as? String).flatMap(Self.iso.date(from:)),
                location: row[3] as? String,
                modifiedAt: (row[4] as? String).flatMap(Self.iso.date(from:))
            )
        }
        return nil
    }

    func put(_ entry: JournalEntry) throws {
        let createdAtStr = entry.createdAt.map { Self.iso.string(from: $0) }
        // A save that changes nothing must not count as a write. The UI saves
        // on every blur/tab-flip/refocus; if those bumped modified_at, the
        // device with the entry ON SCREEN would forever win LWW and remote
        // edits could never land (found the hard way in two-device testing).
        if let current = try currentRow(date: entry.date),
           current.content == entry.content,
           current.location == entry.location {
            return
        }
        // modified_at is store-authoritative: stamped on every write, never
        // taken from the caller (putFromSync differs - by design), and
        // strictly monotonic per entry: two edits inside the same millisecond
        // would otherwise get equal stamps, defeating the in-flight upload
        // guard and LWW ordering.
        var modifiedAtStr = Self.iso.string(from: Date())
        if let previous = try currentRow(date: entry.date)?.modifiedAt,
           modifiedAtStr <= previous,
           let prevDate = Self.iso.date(from: previous) {
            modifiedAtStr = Self.iso.string(from: prevDate.addingTimeInterval(0.001))
        }
        // Data write + dirty marker commit atomically: a crash can never
        // leave a change the sync layer doesn't know about.
        try db.transaction {
            try db.run("""
                INSERT INTO entries (date, content, created_at, location, modified_at) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(date) DO UPDATE SET
                    content = excluded.content,
                    location = excluded.location,
                    modified_at = excluded.modified_at;
            """, entry.date, entry.content, createdAtStr, entry.location, modifiedAtStr)
            try db.run("""
                INSERT INTO sync_state (date, pending) VALUES (?, 1)
                ON CONFLICT(date) DO UPDATE SET pending = 1;
            """, entry.date)
        }
        for continuation in changeContinuations.values {
            continuation.yield(.entryChanged(date: entry.date))
        }
    }

    // MARK: - Sync API (consumed by the CloudKit adapter in phase D3;
    // inert until then)

    /// Local writes as they commit. Multiple consumers supported; each
    /// stream ends when its consumer cancels.
    var localChanges: AsyncStream<LocalChange> {
        let id = UUID()
        return AsyncStream { continuation in
            changeContinuations[id] = continuation
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        changeContinuations[id] = nil
    }

    /// Apply a remote-won entry. Unlike put(): overwrites created_at AND
    /// modified_at with the server's exact values (string-precise - a Date
    /// round-trip could shift fractional digits and break LWW equality),
    /// clears pending, records server system fields. Optionally backs up
    /// the overwritten local row first - all in one transaction.
    func putFromSync(
        date: String,
        content: String,
        createdAt: String?,
        location: String?,
        modifiedAt: String,
        systemFields: Data,
        backupReason: String? = nil
    ) throws {
        try db.transaction {
            if let reason = backupReason {
                try backupRowLocked(date: date, reason: reason)
            }
            try db.run("""
                INSERT INTO entries (date, content, created_at, location, modified_at) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(date) DO UPDATE SET
                    content = excluded.content,
                    created_at = excluded.created_at,
                    location = excluded.location,
                    modified_at = excluded.modified_at;
            """, date, content, createdAt, location, modifiedAt)
            try db.run("""
                INSERT INTO sync_state (date, system_fields, last_synced_modified_at, pending) VALUES (?, ?, ?, 0)
                ON CONFLICT(date) DO UPDATE SET
                    system_fields = excluded.system_fields,
                    last_synced_modified_at = excluded.last_synced_modified_at,
                    pending = 0;
            """, date, Blob(bytes: [UInt8](systemFields)), modifiedAt)
        }
        for continuation in changeContinuations.values {
            continuation.yield(.entryChanged(date: date))
        }
    }

    /// Apply a remote deletion (defensive - this app never issues them).
    func deleteFromSync(date: String, backupReason: String = "remote-delete") throws {
        try db.transaction {
            try backupRowLocked(date: date, reason: backupReason)
            try db.run("DELETE FROM entries WHERE date = ?", date)
            try db.run("DELETE FROM sync_state WHERE date = ?", date)
        }
        for continuation in changeContinuations.values {
            continuation.yield(.entryChanged(date: date))
        }
    }

    func syncRow(date: String) throws -> SyncRow? {
        let stmt = try db.prepare("SELECT date, system_fields, last_synced_modified_at, pending FROM sync_state WHERE date = ?")
        for row in try stmt.run(date) {
            return SyncRow(
                date: row[0] as? String ?? "",
                systemFields: (row[1] as? Blob).map { Data($0.bytes) },
                lastSyncedModifiedAt: row[2] as? String,
                pending: (row[3] as? Int64 ?? 0) != 0
            )
        }
        return nil
    }

    /// Everything needing upload. The modified_at != last_synced comparison
    /// is the healing invariant: it re-catches changes whose pending flag or
    /// engine state got lost (e.g. crash between DB commit and engine-state
    /// save on the CloudKit side).
    func pendingDates() throws -> [String] {
        let stmt = try db.prepare("""
            SELECT e.date FROM entries e
            LEFT JOIN sync_state s ON s.date = e.date
            WHERE s.date IS NULL
               OR s.pending = 1
               OR e.modified_at IS NOT s.last_synced_modified_at
            ORDER BY e.date
        """)
        var out: [String] = []
        for row in try stmt.run() {
            if let d = row[0] as? String { out.append(d) }
        }
        return out
    }

    /// Server acknowledged an upload. Clears pending ONLY if the entry
    /// hasn't been edited again while the upload was in flight.
    func markUploaded(date: String, uploadedModifiedAt: String, systemFields: Data) throws {
        try db.transaction {
            try db.run("""
                INSERT INTO sync_state (date, system_fields, last_synced_modified_at, pending) VALUES (?, ?, ?, 0)
                ON CONFLICT(date) DO UPDATE SET
                    system_fields = excluded.system_fields,
                    last_synced_modified_at = excluded.last_synced_modified_at;
            """, date, Blob(bytes: [UInt8](systemFields)), uploadedModifiedAt)
            try db.run("""
                UPDATE sync_state SET pending = CASE
                    WHEN (SELECT modified_at FROM entries WHERE entries.date = sync_state.date) = ? THEN 0
                    ELSE 1
                END
                WHERE date = ?;
            """, uploadedModifiedAt, date)
        }
    }

    /// Refresh the server change tag without touching entry data (fetch saw
    /// a remote record but local is newer - keep local, remember the tag).
    func storeSystemFields(date: String, _ data: Data) throws {
        try db.run("""
            INSERT INTO sync_state (date, system_fields, pending) VALUES (?, ?, 1)
            ON CONFLICT(date) DO UPDATE SET system_fields = excluded.system_fields;
        """, date, Blob(bytes: [UInt8](data)))
    }

    func syncMeta(key: String) throws -> Data? {
        let stmt = try db.prepare("SELECT value FROM sync_meta WHERE key = ?")
        for row in try stmt.run(key) {
            return (row[0] as? Blob).map { Data($0.bytes) }
        }
        return nil
    }

    func setSyncMeta(key: String, value: Data?) throws {
        if let value {
            try db.run("""
                INSERT INTO sync_meta (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value;
            """, key, Blob(bytes: [UInt8](value)))
        } else {
            try db.run("DELETE FROM sync_meta WHERE key = ?", key)
        }
    }

    /// Account switch / zone recovery: forget every server association but
    /// keep all local data; everything becomes pending again.
    func resetSyncState() throws {
        try db.transaction {
            try db.run("UPDATE sync_state SET system_fields = NULL, last_synced_modified_at = NULL, pending = 1")
            try db.run("INSERT OR IGNORE INTO sync_state (date, pending) SELECT date, 1 FROM entries")
            try db.run("DELETE FROM sync_meta")
        }
    }

    func conflictBackups(for date: String) throws -> [ConflictBackup] {
        let stmt = try db.prepare("""
            SELECT date, content, location, modified_at, backed_up_at, reason
            FROM conflict_backups WHERE date = ? ORDER BY id
        """)
        var out: [ConflictBackup] = []
        for row in try stmt.run(date) {
            out.append(ConflictBackup(
                date: row[0] as? String ?? "",
                content: row[1] as? String ?? "",
                location: row[2] as? String,
                modifiedAt: row[3] as? String,
                backedUpAt: row[4] as? String ?? "",
                reason: row[5] as? String ?? ""
            ))
        }
        return out
    }

    private func currentRow(date: String) throws -> (content: String, location: String?, modifiedAt: String?)? {
        let stmt = try db.prepare("SELECT content, location, modified_at FROM entries WHERE date = ?")
        for row in try stmt.run(date) {
            return (row[0] as? String ?? "", row[1] as? String, row[2] as? String)
        }
        return nil
    }

    /// Must run inside an open transaction.
    private func backupRowLocked(date: String, reason: String) throws {
        try db.run("""
            INSERT INTO conflict_backups (date, content, location, modified_at, backed_up_at, reason)
            SELECT date, content, location, modified_at, ?, ? FROM entries WHERE date = ?
        """, Self.iso.string(from: Date()), reason, date)
    }

    func listDates() throws -> [String] {
        let stmt = try db.prepare("SELECT date FROM entries ORDER BY date DESC")
        var out: [String] = []
        for row in try stmt.run() {
            if let d = row[0] as? String { out.append(d) }
        }
        return out
    }

    func loadRecentLocations() throws -> [String] {
        let stmt = try db.prepare("SELECT DISTINCT location FROM entries WHERE location IS NOT NULL AND location != '' ORDER BY date DESC")
        var seen = Set<String>()
        var out: [String] = []
        for row in try stmt.run() {
            if let s = row[0] as? String, !seen.contains(s) {
                seen.insert(s)
                out.append(s)
            }
        }
        return out
    }

    func loadSummaries() throws -> [EntrySummary] {
        let stmt = try db.prepare("SELECT date, content, created_at, location FROM entries ORDER BY date DESC")
        var out: [EntrySummary] = []
        for row in try stmt.run() {
            let date = row[0] as? String ?? ""
            let content = row[1] as? String ?? ""
            let createdAt = (row[2] as? String).flatMap(Self.iso.date(from:))
            let location = row[3] as? String
            out.append(EntrySummary(
                date: date,
                preview: EntryUtil.extractPreview(from: content),
                createdAt: createdAt,
                location: location
            ))
        }
        return out
    }
}
