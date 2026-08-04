import Foundation

// Pure last-writer-wins logic. Zero CloudKit imports: every decision here is
// unit-testable in CI, and both devices running this same code on the same
// inputs is what makes the system converge.

/// A remote entry as decoded from a CKRecord (by JournalRecordCoder).
struct RemoteEntry: Sendable, Equatable {
    let date: String
    let content: String
    let createdAt: String?
    let location: String?
    /// ISO8601 with fractional seconds - the LWW clock.
    let modifiedAt: String
}

enum FetchResolution: Sendable, Equatable {
    /// Remote is newer (or no local row): write it locally, clear pending.
    case applyRemote
    /// Local is newer: keep local content + pending, but remember the
    /// server's system fields so the next upload carries a fresh change tag.
    case keepLocalStoreTag
    /// Same clock, same content: record the tag, nothing else to do.
    case identical
}

enum ConflictResolution: Sendable, Equatable {
    /// Local is newer: adopt the server's change tag, re-upload local.
    case localWinsReupload
    /// Server is newer (or equal-stamp tie): overwrite local, back it up.
    case remoteWins
    /// Same clock, same content: adopt tag, clear pending.
    case identical
}

enum SyncReconciler {
    /// A remote record arrived via fetch. `localModifiedAt` nil = no local row.
    static func resolveFetch(
        localModifiedAt: String?,
        localContentEqualsRemote: Bool,
        remote: RemoteEntry
    ) -> FetchResolution {
        guard let local = localModifiedAt else { return .applyRemote }
        switch compare(local, remote.modifiedAt) {
        case .orderedAscending:
            return .applyRemote
        case .orderedDescending:
            return .keepLocalStoreTag
        case .orderedSame:
            // Equal stamps with different content = clock pathology. Prefer
            // the server copy deterministically so both devices converge.
            return localContentEqualsRemote ? .identical : .applyRemote
        }
    }

    /// An upload was rejected with the server's current copy.
    static func resolveConflict(
        localModifiedAt: String,
        localContentEqualsServer: Bool,
        server: RemoteEntry
    ) -> ConflictResolution {
        switch compare(localModifiedAt, server.modifiedAt) {
        case .orderedDescending:
            return .localWinsReupload
        case .orderedAscending:
            return .remoteWins
        case .orderedSame:
            return localContentEqualsServer ? .identical : .remoteWins
        }
    }

    /// Lexicographic compare of normalized ISO8601 stamps. Fixed-width UTC
    /// strings sort chronologically; normalization guards against a writer
    /// that omitted fractional seconds ("...:00Z" vs "...:00.000Z" would
    /// otherwise compare wrongly).
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let na = normalize(a)
        let nb = normalize(b)
        if na < nb { return .orderedAscending }
        if na > nb { return .orderedDescending }
        return .orderedSame
    }

    /// "2026-08-04T09:00:00Z" -> "2026-08-04T09:00:00.000Z"; already-fractional
    /// stamps pass through. Non-conforming input is returned unchanged.
    static func normalize(_ stamp: String) -> String {
        guard stamp.hasSuffix("Z"), !stamp.contains(".") else { return stamp }
        return String(stamp.dropLast()) + ".000Z"
    }
}
