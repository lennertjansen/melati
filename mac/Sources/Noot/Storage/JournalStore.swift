import Foundation
@preconcurrency import SQLiteDB

enum JournalStoreError: Error {
    case wrongKey
}

actor JournalStore {
    private let db: Connection
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
    }

    func get(date: String) throws -> JournalEntry? {
        let stmt = try db.prepare("SELECT date, content, created_at, location FROM entries WHERE date = ?")
        for row in try stmt.run(date) {
            return JournalEntry(
                date: row[0] as? String ?? "",
                content: row[1] as? String ?? "",
                createdAt: (row[2] as? String).flatMap(Self.iso.date(from:)),
                location: row[3] as? String
            )
        }
        return nil
    }

    func put(_ entry: JournalEntry) throws {
        let createdAtStr = entry.createdAt.map { Self.iso.string(from: $0) }
        try db.run("""
            INSERT INTO entries (date, content, created_at, location) VALUES (?, ?, ?, ?)
            ON CONFLICT(date) DO UPDATE SET content = excluded.content, location = excluded.location;
        """, entry.date, entry.content, createdAtStr, entry.location)
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
