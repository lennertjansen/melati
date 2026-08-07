import CloudKit
import XCTest

final class SyncReconcilerTests: XCTestCase {
    private func remote(_ modifiedAt: String, content: String = "r") -> RemoteEntry {
        RemoteEntry(date: "2026-08-04", content: content, createdAt: nil, location: nil, modifiedAt: modifiedAt)
    }

    /// Convenience: containment flags computed from real contents, the way
    /// CloudSyncService computes them.
    private func fetch(
        local: String?, base: String?, localContent: String = "l",
        localLocation: String? = nil, remote r: RemoteEntry
    ) -> FetchResolution {
        SyncReconciler.resolveFetch(
            localModifiedAt: local,
            lastSyncedModifiedAt: base,
            localEqualsRemote: local != nil && localContent == r.content && localLocation == r.location,
            localContainsRemote: EntryMerge.contains(local == nil ? "" : localContent, r.content),
            remoteContainsLocal: EntryMerge.contains(r.content, local == nil ? "" : localContent),
            remote: r
        )
    }

    // MARK: resolveFetch - no local / equality

    func testFetchNoLocalRowAppliesRemote() {
        let r = fetch(local: nil, base: nil, remote: remote("2026-08-04T10:00:00.000Z"))
        XCTAssertEqual(r, .applyRemote)
    }

    func testFetchEqualStampSameContentIsIdentical() {
        let r = fetch(local: "2026-08-04T10:00:00.000Z", base: nil, localContent: "same",
                      remote: remote("2026-08-04T10:00:00.000Z", content: "same"))
        XCTAssertEqual(r, .identical)
    }

    func testFetchSameContentNewerStampAdoptsRemoteClock() {
        let r = fetch(local: "2026-08-04T09:00:00.000Z", base: nil, localContent: "same",
                      remote: remote("2026-08-04T10:00:00.000Z", content: "same"))
        XCTAssertEqual(r, .applyRemote)
    }

    // MARK: resolveFetch - fast-forward (no local edits since last sync)

    func testFastForwardAppliesNewerRemote() {
        // The normal propagation case: deletions and rewrites apply verbatim.
        let r = fetch(local: "2026-08-04T09:00:00.000Z", base: "2026-08-04T09:00:00.000Z",
                      localContent: "old text", remote: remote("2026-08-04T10:00:00.000Z", content: "rewritten"))
        XCTAssertEqual(r, .applyRemote)
    }

    func testFastForwardEqualStampDifferentContentPrefersServer() {
        // Clock pathology: deterministic server preference converges both sides.
        let r = fetch(local: "2026-08-04T10:00:00.000Z", base: "2026-08-04T10:00:00.000Z",
                      remote: remote("2026-08-04T10:00:00.000Z", content: "server"))
        XCTAssertEqual(r, .applyRemote)
    }

    func testFastForwardOlderRemoteKeepsLocal() {
        // Server regression (shouldn't happen): keep ours.
        let r = fetch(local: "2026-08-04T11:00:00.000Z", base: "2026-08-04T11:00:00.000Z",
                      remote: remote("2026-08-04T10:00:00.000Z"))
        XCTAssertEqual(r, .keepLocalStoreTag)
    }

    // MARK: resolveFetch - local edits, remote already seen

    func testSeenRemoteKeepsLocalEdits() {
        // Remote is exactly the base we edited on top of: ours supersedes.
        let r = fetch(local: "2026-08-04T11:00:00.000Z", base: "2026-08-04T10:00:00.000Z",
                      remote: remote("2026-08-04T10:00:00.000Z"))
        XCTAssertEqual(r, .keepLocalStoreTag)
    }

    // MARK: resolveFetch - forks (the 2026-08-06 incident class)

    func testStaleStartForkMergesInsteadOfDiscardingOlderRemote() {
        // THE incident: phone typed on an empty/stale base (never synced
        // today's record, base nil), Mac's morning text is on the server
        // with an OLDER stamp. v1 LWW kept local and the morning text never
        // landed. v2: genuine fork -> merge.
        let r = fetch(local: "2026-08-06T09:26:00.000Z", base: nil,
                      localContent: "reverse-sync-test 0955",
                      remote: remote("2026-08-06T08:00:00.000Z", content: "a whole morning of writing"))
        XCTAssertEqual(r, .mergeAndUpload)
    }

    func testForkWithNewerRemoteAlsoMerges() {
        // Both sides moved past the shared base: merge regardless of who is newer.
        let r = fetch(local: "2026-08-04T10:30:00.000Z", base: "2026-08-04T09:00:00.000Z",
                      localContent: "local fork", remote: remote("2026-08-04T11:00:00.000Z", content: "remote fork"))
        XCTAssertEqual(r, .mergeAndUpload)
    }

    func testForkLocalAlreadyContainsRemoteKeepsLocal() {
        // A previous merge (or buffer absorption) already stacked the remote
        // text into local: nothing new to take.
        let r = fetch(local: "2026-08-04T10:30:00.000Z", base: nil,
                      localContent: "their text\n\nmy text",
                      remote: remote("2026-08-04T10:00:00.000Z", content: "their text"))
        XCTAssertEqual(r, .keepLocalStoreTag)
    }

    func testForkRemoteContainsLocalAppliesRemote() {
        // The other device merged first: its copy includes ours.
        let r = fetch(local: "2026-08-04T10:00:00.000Z", base: nil,
                      localContent: "my text",
                      remote: remote("2026-08-04T10:30:00.000Z", content: "my text\n\ntheir text"))
        XCTAssertEqual(r, .applyRemote)
    }

    func testForkEmptyLocalAppliesRemote() {
        // Empty content is contained in anything: no merge for a blank side.
        let r = fetch(local: "2026-08-04T10:30:00.000Z", base: nil,
                      localContent: "", remote: remote("2026-08-04T10:00:00.000Z", content: "text"))
        XCTAssertEqual(r, .applyRemote)
    }

    // MARK: resolveConflict

    private func conflict(
        local: String, base: String?, localContent: String = "l", server s: RemoteEntry
    ) -> ConflictResolution {
        SyncReconciler.resolveConflict(
            localModifiedAt: local,
            lastSyncedModifiedAt: base,
            localEqualsServer: localContent == s.content && s.location == nil,
            localContainsServer: EntryMerge.contains(localContent, s.content),
            serverContainsLocal: EntryMerge.contains(s.content, localContent),
            server: s
        )
    }

    func testConflictAgainstSeenServerVersionReuploads() {
        let r = conflict(local: "2026-08-04T11:00:00.000Z", base: "2026-08-04T10:00:00.000Z",
                         server: remote("2026-08-04T10:00:00.000Z"))
        XCTAssertEqual(r, .localWinsReupload)
    }

    func testConflictSameContentIdentical() {
        let r = conflict(local: "2026-08-04T10:00:00.000Z", base: nil, localContent: "same",
                         server: remote("2026-08-04T10:05:00.000Z", content: "same"))
        XCTAssertEqual(r, .identical)
    }

    func testConflictForkMerges() {
        // First upload from a device that typed on a stale base ("record to
        // insert already exists"): server text is unseen -> merge, not clobber.
        let r = conflict(local: "2026-08-06T09:26:00.000Z", base: nil,
                         localContent: "reverse-sync-test 0955",
                         server: remote("2026-08-06T08:00:00.000Z", content: "a whole morning of writing"))
        XCTAssertEqual(r, .mergeAndReupload)
    }

    func testConflictServerContainsLocalTakesServer() {
        let r = conflict(local: "2026-08-04T10:00:00.000Z", base: nil,
                         localContent: "mine",
                         server: remote("2026-08-04T10:30:00.000Z", content: "mine\n\ntheirs"))
        XCTAssertEqual(r, .remoteWins)
    }

    // MARK: clock comparison

    func testFractionalSecondsOrderCorrectly() {
        XCTAssertEqual(SyncReconciler.compare("2026-08-04T10:00:00.100Z", "2026-08-04T10:00:00.200Z"), .orderedAscending)
        XCTAssertEqual(SyncReconciler.compare("2026-08-04T10:00:00.200Z", "2026-08-04T10:00:00.100Z"), .orderedDescending)
        XCTAssertEqual(SyncReconciler.compare("2026-08-04T10:00:00.100Z", "2026-08-04T10:00:00.100Z"), .orderedSame)
    }

    func testMissingFractionalSecondsNormalizeCorrectly() {
        // Raw lexicographic would say "...00.000Z" < "...00Z" (46 < 90);
        // normalization must make them EQUAL.
        XCTAssertEqual(SyncReconciler.compare("2026-08-04T10:00:00Z", "2026-08-04T10:00:00.000Z"), .orderedSame)
        XCTAssertEqual(SyncReconciler.compare("2026-08-04T10:00:01Z", "2026-08-04T10:00:00.900Z"), .orderedDescending)
        XCTAssertEqual(SyncReconciler.compare("2026-08-04T10:00:00Z", "2026-08-04T10:00:00.100Z"), .orderedAscending)
    }

    func testCrossDayComparison() {
        XCTAssertEqual(SyncReconciler.compare("2026-08-03T23:59:59.999Z", "2026-08-04T00:00:00.000Z"), .orderedAscending)
    }
}

final class EntryMergeTests: XCTestCase {
    func testMergePutsOlderAboveNewer() {
        let merged = EntryMerge.merge(
            aContent: "typed later on the phone", aStamp: "2026-08-06T09:26:00.000Z",
            bContent: "written in the morning on the mac", bStamp: "2026-08-06T08:00:00.000Z"
        )
        XCTAssertEqual(merged, "written in the morning on the mac\n\ntyped later on the phone")
    }

    func testMergeIsDeterministicRegardlessOfArgumentOrder() {
        // Both devices merge the same fork -> identical bytes -> convergence.
        let ab = EntryMerge.merge(aContent: "A", aStamp: "2026-08-06T08:00:00.000Z",
                                  bContent: "B", bStamp: "2026-08-06T09:00:00.000Z")
        let ba = EntryMerge.merge(aContent: "B", aStamp: "2026-08-06T09:00:00.000Z",
                                  bContent: "A", bStamp: "2026-08-06T08:00:00.000Z")
        XCTAssertEqual(ab, ba)
        XCTAssertEqual(ab, "A\n\nB")
    }

    func testMergeEqualStampsOrdersByContent() {
        let xy = EntryMerge.merge(aContent: "x", aStamp: "2026-08-06T08:00:00.000Z",
                                  bContent: "y", bStamp: "2026-08-06T08:00:00.000Z")
        let yx = EntryMerge.merge(aContent: "y", aStamp: "2026-08-06T08:00:00.000Z",
                                  bContent: "x", bStamp: "2026-08-06T08:00:00.000Z")
        XCTAssertEqual(xy, yx)
    }

    func testStackTrimsBlankEdgesOnly() {
        let merged = EntryMerge.stack(older: "morning text\n\n", newer: "\nevening text")
        XCTAssertEqual(merged, "morning text\n\nevening text")
    }

    func testStackWithEmptySideReturnsOther() {
        XCTAssertEqual(EntryMerge.stack(older: "", newer: "text"), "text")
        XCTAssertEqual(EntryMerge.stack(older: "text", newer: "\n"), "text")
    }

    func testContainsIsTrimmedVerbatim() {
        XCTAssertTrue(EntryMerge.contains("their text\n\nmy text", "their text"))
        XCTAssertTrue(EntryMerge.contains("anything", ""))
        XCTAssertTrue(EntryMerge.contains("anything", "\n  \n"))
        XCTAssertFalse(EntryMerge.contains("short", "something else"))
    }

    func testDoubleMergeIsIdempotentViaContainment() {
        // After a merge, re-encountering either source must not re-merge:
        // the merged text contains both sides verbatim.
        let merged = EntryMerge.merge(aContent: "mine", aStamp: "2026-08-06T09:00:00.000Z",
                                      bContent: "theirs", bStamp: "2026-08-06T08:00:00.000Z")
        XCTAssertTrue(EntryMerge.contains(merged, "mine"))
        XCTAssertTrue(EntryMerge.contains(merged, "theirs"))
    }

    // MARK: prefix-aware merging (the take2/take3 duplication wart)

    func testSharedPrefixIsNotDuplicated() {
        // Both devices appended to the same synced base: base appears once,
        // older fork verbatim, newer fork's novel tail below.
        let merged = EntryMerge.merge(
            aContent: "shared base\n\nmac addition", aStamp: "2026-08-06T10:00:00.000Z",
            bContent: "shared base\n\nphone addition", bStamp: "2026-08-06T11:00:00.000Z"
        )
        XCTAssertEqual(merged, "shared base\n\nmac addition\n\nphone addition")
    }

    func testSharedPrefixMergeKeepsListStructure() {
        // Line-based split: the older version stays verbatim even for
        // single-newline structures like lists.
        let merged = EntryMerge.merge(
            aContent: "- a\n- b", aStamp: "2026-08-06T10:00:00.000Z",
            bContent: "- a\n- c", bStamp: "2026-08-06T11:00:00.000Z"
        )
        XCTAssertEqual(merged, "- a\n- b\n\n- c")
    }

    func testDisjointContentStillStacksWhole() {
        let merged = EntryMerge.merge(
            aContent: "completely different", aStamp: "2026-08-06T10:00:00.000Z",
            bContent: "no overlap at all", bStamp: "2026-08-06T11:00:00.000Z"
        )
        XCTAssertEqual(merged, "completely different\n\nno overlap at all")
    }

    func testRemergingSourceAgainstResultConverges() {
        // The failure mode that caused duplication: the merged result meets
        // one of its sources again. Guards must return the result unchanged.
        let older = "shared\n\nmac part"
        let newer = "shared\n\nphone part"
        let merged = EntryMerge.merge(
            aContent: older, aStamp: "2026-08-06T10:00:00.000Z",
            bContent: newer, bStamp: "2026-08-06T11:00:00.000Z"
        )
        // merged is newest; re-encounter each source as the older side.
        XCTAssertEqual(EntryMerge.mergeOrdered(older: older, newer: merged), merged)
        XCTAssertEqual(EntryMerge.mergeOrdered(older: newer, newer: merged), merged)
    }

    func testLinearExtensionReturnsNewer() {
        // Newer strictly extends older: nothing novel in the older tail.
        let merged = EntryMerge.mergeOrdered(older: "day one", newer: "day one\n\nday two")
        XCTAssertEqual(merged, "day one\n\nday two")
    }

    func testForkDeletionKeepsContent() {
        // Newer deleted the tail while forked: fork semantics never discard.
        let merged = EntryMerge.mergeOrdered(older: "keep\n\nthis text", newer: "keep")
        XCTAssertEqual(merged, "keep\n\nthis text")
    }
}

final class JournalRecordCoderTests: XCTestCase {
    // CKRecord works fully offline - no account, no entitlements needed.

    func testEncodeDecodeRoundTrip() {
        let record = CKRecord(recordType: SyncSchema.recordType, recordID: SyncSchema.recordID(dateKey: "2026-08-04"))
        JournalRecordCoder.encode(
            date: "2026-08-04",
            content: "# Hello\ntoday was good",
            createdAt: "2026-08-04T08:00:00.000Z",
            location: "Amsterdam",
            modifiedAt: "2026-08-04T09:30:00.123Z",
            onto: record
        )

        let decoded = JournalRecordCoder.decode(record)
        XCTAssertEqual(decoded, RemoteEntry(
            date: "2026-08-04",
            content: "# Hello\ntoday was good",
            createdAt: "2026-08-04T08:00:00.000Z",
            location: "Amsterdam",
            modifiedAt: "2026-08-04T09:30:00.123Z"
        ))
    }

    func testUserDataLivesInEncryptedValuesOnly() {
        let record = CKRecord(recordType: SyncSchema.recordType, recordID: SyncSchema.recordID(dateKey: "2026-08-04"))
        JournalRecordCoder.encode(
            date: "2026-08-04", content: "secret", createdAt: nil,
            location: "secret place", modifiedAt: "2026-08-04T09:00:00.000Z",
            onto: record
        )
        // Plain (queryable, Apple-readable-without-ADP) keys must never carry
        // user text. schemaVersion is the only allowed plain field.
        XCTAssertNil(record["content"])
        XCTAssertNil(record["location"])
        XCTAssertNil(record["modifiedAt"])
        XCTAssertEqual(record["schemaVersion"] as? Int64, SyncSchema.schemaVersion)
        XCTAssertEqual(record.encryptedValues["content"] as? String, "secret")
    }

    func testDecodeNilFieldsOmitted() {
        let record = CKRecord(recordType: SyncSchema.recordType, recordID: SyncSchema.recordID(dateKey: "2026-08-05"))
        JournalRecordCoder.encode(
            date: "2026-08-05", content: "", createdAt: nil, location: nil,
            modifiedAt: "2026-08-05T00:00:00.000Z", onto: record
        )
        let decoded = JournalRecordCoder.decode(record)
        XCTAssertEqual(decoded?.content, "")
        XCTAssertNil(decoded?.createdAt)
        XCTAssertNil(decoded?.location)
    }

    func testDecodeRejectsForeignRecordType() {
        let record = CKRecord(recordType: "SomethingElse", recordID: SyncSchema.recordID(dateKey: "2026-08-04"))
        record.encryptedValues["content"] = "x"
        XCTAssertNil(JournalRecordCoder.decode(record))
    }

    func testDecodeRejectsMissingContent() {
        let record = CKRecord(recordType: SyncSchema.recordType, recordID: SyncSchema.recordID(dateKey: "2026-08-04"))
        record.encryptedValues["modifiedAt"] = "2026-08-04T09:00:00.000Z"
        XCTAssertNil(JournalRecordCoder.decode(record))
    }

    func testDecodeMissingModifiedAtFallsBackToEpoch() {
        // Fresh unsaved record has no modificationDate either -> epoch. The
        // entry survives (never drop data), it just loses every version contest.
        let record = CKRecord(recordType: SyncSchema.recordType, recordID: SyncSchema.recordID(dateKey: "2026-08-04"))
        record.encryptedValues["content"] = "orphan"
        let decoded = JournalRecordCoder.decode(record)
        XCTAssertEqual(decoded?.modifiedAt, "1970-01-01T00:00:00.000Z")
    }

    func testRecordIdentityMatchesDateKey() {
        let id = SyncSchema.recordID(dateKey: "2026-12-31")
        XCTAssertEqual(id.recordName, "2026-12-31")
        XCTAssertEqual(id.zoneID.zoneName, "Journal")
    }
}
