import Foundation

// Sync-facing value types. Deliberately no CloudKit imports anywhere in
// Storage/ - the CloudKit adapter (phase D3) translates at its own boundary,
// which keeps everything here unit-testable in CI.

/// Per-entry sync bookkeeping, one row per entries.date (may outlive the
/// entry itself if a remote delete ever removes the row).
struct SyncRow: Sendable, Equatable {
    let date: String
    /// Archived CKRecord system fields from the last server contact;
    /// nil = this entry has never been uploaded.
    let systemFields: Data?
    /// entries.modified_at value the server last acknowledged.
    let lastSyncedModifiedAt: String?
    /// true = local change not yet confirmed uploaded.
    let pending: Bool
}

enum LocalChange: Sendable, Equatable {
    case entryChanged(date: String)
}

/// A conflict_backups row: whatever whole-entry LWW overwrote, kept so no
/// text is ever silently destroyed.
struct ConflictBackup: Sendable, Equatable {
    let date: String
    let content: String
    let location: String?
    let modifiedAt: String?
    let backedUpAt: String
    let reason: String
}
