import CloudKit
import Foundation

// The ONLY sync file that imports CloudKit besides the D3 engine adapter.
// CKRecord construction and encryptedValues work fully offline, so this stays
// unit-testable without an iCloud account or entitlements.

enum SyncSchema {
    static let zoneName = "Journal"
    static let recordType = "JournalEntry"
    /// Payload version, for future field evolution.
    static let schemaVersion: Int64 = 1

    static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    static func recordID(dateKey: String) -> CKRecord.ID {
        CKRecord.ID(recordName: dateKey, zoneID: zoneID)
    }
}

enum JournalRecordCoder {
    /// Write entry fields onto a record. User data goes in encryptedValues
    /// (E2E under Advanced Data Protection). Timestamps stay STRINGS so LWW
    /// comparisons are byte-identical to the SQLite column.
    static func encode(
        date: String,
        content: String,
        createdAt: String?,
        location: String?,
        modifiedAt: String,
        onto record: CKRecord
    ) {
        record.encryptedValues["content"] = content
        record.encryptedValues["location"] = location
        record.encryptedValues["createdAt"] = createdAt
        record.encryptedValues["modifiedAt"] = modifiedAt
        record["schemaVersion"] = SyncSchema.schemaVersion
    }

    /// nil when the record has no readable content (foreign/corrupt record) -
    /// callers skip those rather than guessing.
    static func decode(_ record: CKRecord) -> RemoteEntry? {
        guard record.recordType == SyncSchema.recordType,
              let content = record.encryptedValues["content"] as? String else {
            return nil
        }
        // modifiedAt should always exist; records written by a future or
        // buggy client fall back to the server's own modification date, and
        // as a last resort the epoch (loses LWW but never drops data).
        let modifiedAt = (record.encryptedValues["modifiedAt"] as? String)
            ?? record.modificationDate.map { isoFormatter.string(from: $0) }
            ?? "1970-01-01T00:00:00.000Z"
        return RemoteEntry(
            date: record.recordID.recordName,
            content: content,
            createdAt: record.encryptedValues["createdAt"] as? String,
            location: record.encryptedValues["location"] as? String,
            modifiedAt: modifiedAt
        )
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
