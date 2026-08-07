import CloudKit
import XCTest

final class AccountChangePlanTests: XCTestCase {
    func testSignInResetsAndRestarts() {
        let plan = SyncEdgePolicy.plan(for: .signIn)
        XCTAssertTrue(plan.resetSyncState)
        XCTAssertTrue(plan.restartEngine)
        XCTAssertNil(plan.statusWhenDone)
    }

    func testSignOutResetsRestartsAndGoesOff() {
        // Data is kept, associations forgotten; the fresh engine idles so
        // the eventual sign-in event still reaches us. UI shows off.
        let plan = SyncEdgePolicy.plan(for: .signOut)
        XCTAssertTrue(plan.resetSyncState)
        XCTAssertTrue(plan.restartEngine)
        XCTAssertEqual(plan.statusWhenDone, .off)
    }

    func testSwitchAccountsResetsAndMerges() {
        let plan = SyncEdgePolicy.plan(for: .switchAccounts)
        XCTAssertTrue(plan.resetSyncState)
        XCTAssertTrue(plan.restartEngine)
        XCTAssertNil(plan.statusWhenDone)
    }

}

final class UploadFailureActionTests: XCTestCase {
    func testServerRecordChangedResolvesConflict() {
        XCTAssertEqual(SyncEdgePolicy.uploadFailureAction(for: .serverRecordChanged), .resolveConflict)
    }

    func testZoneGoneRecreates() {
        XCTAssertEqual(SyncEdgePolicy.uploadFailureAction(for: .zoneNotFound), .recreateZone)
        XCTAssertEqual(SyncEdgePolicy.uploadFailureAction(for: .userDeletedZone), .recreateZone)
    }

    func testQuotaExceededIsQuota() {
        XCTAssertEqual(SyncEdgePolicy.uploadFailureAction(for: .quotaExceeded), .quotaFull)
    }

    func testOfflineRetriesQuietly() {
        // Offline writing is normal diary use - no error line.
        XCTAssertEqual(SyncEdgePolicy.uploadFailureAction(for: .networkUnavailable), .retryQuietly)
        XCTAssertEqual(SyncEdgePolicy.uploadFailureAction(for: .networkFailure), .retryQuietly)
        XCTAssertEqual(SyncEdgePolicy.uploadFailureAction(for: .requestRateLimited), .retryQuietly)
    }

    func testUnexpectedFailureShowsError() {
        XCTAssertEqual(SyncEdgePolicy.uploadFailureAction(for: .internalError), .retryShowError)
        XCTAssertEqual(SyncEdgePolicy.uploadFailureAction(for: .serverRejectedRequest), .retryShowError)
    }
}

final class FetchFailureQuietTests: XCTestCase {
    func testOfflineFetchIsQuiet() {
        XCTAssertTrue(SyncEdgePolicy.fetchFailureIsQuiet(.networkUnavailable))
        XCTAssertTrue(SyncEdgePolicy.fetchFailureIsQuiet(.notAuthenticated))
    }

    func testUnexpectedFetchFailureIsNot() {
        XCTAssertFalse(SyncEdgePolicy.fetchFailureIsQuiet(.internalError))
    }
}
