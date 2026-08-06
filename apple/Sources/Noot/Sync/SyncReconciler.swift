import Foundation

// Pure reconciliation logic. Zero CloudKit imports: every decision here is
// unit-testable in CI, and both devices running this same code on the same
// inputs is what makes the system converge.
//
// v2 (post-incident 2026-08-06): three-way, not last-writer-wins. The stamp
// alone cannot distinguish "I edited the current version" from "I edited a
// stale base" - and the second case is exactly how a fresh phone save wiped
// a morning of Mac writing. lastSyncedModifiedAt is the base marker: local
// edits on a base older than the incoming version = a genuine fork, and
// forks MERGE (older content above, newer below - see EntryMerge). Content
// is never discarded by reconciliation.

/// A remote entry as decoded from a CKRecord (by JournalRecordCoder).
struct RemoteEntry: Sendable, Equatable {
    let date: String
    let content: String
    let createdAt: String?
    let location: String?
    /// ISO8601 with fractional seconds - the version clock.
    let modifiedAt: String
}

enum FetchResolution: Sendable, Equatable {
    /// Remote supersedes local (no local row, no local edits, or local is
    /// fully contained in remote): write it locally, clear pending.
    case applyRemote
    /// Local supersedes remote (remote already seen, or fully contained in
    /// local): keep local content + pending, but remember the server's
    /// system fields so the next upload carries a fresh change tag.
    case keepLocalStoreTag
    /// Same clock, same content: record the tag, nothing else to do.
    case identical
    /// Genuine fork with disjoint content: write the merged entry as a new
    /// local edit (pending upload) and adopt the server tag.
    case mergeAndUpload
}

enum ConflictResolution: Sendable, Equatable {
    /// Server copy is already seen or contained in local: adopt the change
    /// tag, re-upload local.
    case localWinsReupload
    /// Local is fully contained in the server copy: take the server's.
    case remoteWins
    /// Same content: adopt tag, clear pending.
    case identical
    /// Fork with disjoint content: store merged locally, adopt tag, re-upload.
    case mergeAndReupload
}

enum SyncReconciler {
    /// A remote record arrived via fetch.
    /// - localModifiedAt: nil = no local row.
    /// - lastSyncedModifiedAt: the local stamp the server last acknowledged
    ///   (nil = never synced). local == lastSynced means "no local edits
    ///   since my last sync" - the fast-forward case.
    /// - localEqualsRemote: strict content+location equality.
    /// - localContainsRemote / remoteContainsLocal: trimmed verbatim
    ///   containment (EntryMerge.contains) - one side already absorbed the
    ///   other, e.g. after a previous merge.
    static func resolveFetch(
        localModifiedAt: String?,
        lastSyncedModifiedAt: String?,
        localEqualsRemote: Bool,
        localContainsRemote: Bool,
        remoteContainsLocal: Bool,
        remote: RemoteEntry
    ) -> FetchResolution {
        guard let local = localModifiedAt else { return .applyRemote }

        if localEqualsRemote {
            // Stamps may still differ (e.g. the other device re-uploaded the
            // same text); same-stamp is a pure ack, otherwise adopt the
            // remote stamp so both clocks agree.
            return compare(local, remote.modifiedAt) == .orderedSame ? .identical : .applyRemote
        }

        // No local edits since the last sync: fast-forward. This is normal
        // propagation - deletions and rewrites apply verbatim, no merging.
        let localIsClean = lastSyncedModifiedAt.map { compare(local, $0) == .orderedSame } ?? false
        if localIsClean {
            // Equal-stamp-different-content is clock pathology: prefer the
            // server copy deterministically so both devices converge.
            return compare(local, remote.modifiedAt) == .orderedDescending ? .keepLocalStoreTag : .applyRemote
        }

        // Local has unsynced edits. If the remote version is the base we
        // already synced against (or older), our edits supersede it.
        if let base = lastSyncedModifiedAt, compare(remote.modifiedAt, base) != .orderedDescending {
            return .keepLocalStoreTag
        }

        // Fork: local edited on a stale (or unknown) base AND the server
        // moved. Never discard content.
        if localContainsRemote { return .keepLocalStoreTag }
        if remoteContainsLocal { return .applyRemote }
        return .mergeAndUpload
    }

    /// An upload was rejected with the server's current copy. Uploads only
    /// happen for pending (locally edited) entries, so this is always the
    /// "local has edits" half of the matrix.
    static func resolveConflict(
        localModifiedAt: String,
        lastSyncedModifiedAt: String?,
        localEqualsServer: Bool,
        localContainsServer: Bool,
        serverContainsLocal: Bool,
        server: RemoteEntry
    ) -> ConflictResolution {
        if localEqualsServer { return .identical }

        if let base = lastSyncedModifiedAt, compare(server.modifiedAt, base) != .orderedDescending {
            return .localWinsReupload
        }
        if localContainsServer { return .localWinsReupload }
        if serverContainsLocal { return .remoteWins }
        return .mergeAndReupload
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
