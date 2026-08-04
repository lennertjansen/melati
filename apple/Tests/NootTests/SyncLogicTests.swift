import CloudKit
import XCTest

final class SyncReconcilerTests: XCTestCase {
    private func remote(_ modifiedAt: String, content: String = "r") -> RemoteEntry {
        RemoteEntry(date: "2026-08-04", content: content, createdAt: nil, location: nil, modifiedAt: modifiedAt)
    }

    // MARK: resolveFetch matrix

    func testFetchNoLocalRowAppliesRemote() {
        let r = SyncReconciler.resolveFetch(
            localModifiedAt: nil, localContentEqualsRemote: false,
            remote: remote("2026-08-04T10:00:00.000Z"))
        XCTAssertEqual(r, .applyRemote)
    }

    func testFetchRemoteNewerAppliesRemote() {
        let r = SyncReconciler.resolveFetch(
            localModifiedAt: "2026-08-04T09:00:00.000Z", localContentEqualsRemote: false,
            remote: remote("2026-08-04T10:00:00.000Z"))
        XCTAssertEqual(r, .applyRemote)
    }

    func testFetchLocalNewerKeepsLocalStoresTag() {
        let r = SyncReconciler.resolveFetch(
            localModifiedAt: "2026-08-04T11:00:00.000Z", localContentEqualsRemote: false,
            remote: remote("2026-08-04T10:00:00.000Z"))
        XCTAssertEqual(r, .keepLocalStoreTag)
    }

    func testFetchEqualStampSameContentIsIdentical() {
        let r = SyncReconciler.resolveFetch(
            localModifiedAt: "2026-08-04T10:00:00.000Z", localContentEqualsRemote: true,
            remote: remote("2026-08-04T10:00:00.000Z"))
        XCTAssertEqual(r, .identical)
    }

    func testFetchEqualStampDifferentContentPrefersServer() {
        // Clock pathology: deterministic server preference converges both sides.
        let r = SyncReconciler.resolveFetch(
            localModifiedAt: "2026-08-04T10:00:00.000Z", localContentEqualsRemote: false,
            remote: remote("2026-08-04T10:00:00.000Z"))
        XCTAssertEqual(r, .applyRemote)
    }

    // MARK: resolveConflict matrix

    func testConflictLocalNewerWinsReupload() {
        let r = SyncReconciler.resolveConflict(
            localModifiedAt: "2026-08-04T11:00:00.000Z", localContentEqualsServer: false,
            server: remote("2026-08-04T10:00:00.000Z"))
        XCTAssertEqual(r, .localWinsReupload)
    }

    func testConflictServerNewerWins() {
        let r = SyncReconciler.resolveConflict(
            localModifiedAt: "2026-08-04T09:00:00.000Z", localContentEqualsServer: false,
            server: remote("2026-08-04T10:00:00.000Z"))
        XCTAssertEqual(r, .remoteWins)
    }

    func testConflictEqualStampSameContentIdentical() {
        let r = SyncReconciler.resolveConflict(
            localModifiedAt: "2026-08-04T10:00:00.000Z", localContentEqualsServer: true,
            server: remote("2026-08-04T10:00:00.000Z"))
        XCTAssertEqual(r, .identical)
    }

    func testConflictEqualStampDifferentContentPrefersServer() {
        let r = SyncReconciler.resolveConflict(
            localModifiedAt: "2026-08-04T10:00:00.000Z", localContentEqualsServer: false,
            server: remote("2026-08-04T10:00:00.000Z"))
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
        // entry survives (never drop data), it just loses every LWW contest.
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
