import XCTest

final class SyncActivityTests: XCTestCase {
    func testInitialStatusIsIdle() {
        XCTAssertEqual(SyncActivity().status, .idle)
    }

    func testBeginMakesSyncing() {
        var a = SyncActivity()
        a.begin()
        XCTAssertEqual(a.status, .syncing)
    }

    func testEndReturnsToIdle() {
        var a = SyncActivity()
        a.begin()
        a.end()
        XCTAssertEqual(a.status, .idle)
    }

    func testOverlappingOperationsStaySyncingUntilAllEnd() {
        var a = SyncActivity()
        a.begin() // fetch
        a.begin() // send
        a.end()
        XCTAssertEqual(a.status, .syncing)
        a.end()
        XCTAssertEqual(a.status, .idle)
    }

    func testUnbalancedEndDoesNotUnderflow() {
        var a = SyncActivity()
        a.end()
        XCTAssertEqual(a.status, .idle)
        a.begin()
        XCTAssertEqual(a.status, .syncing)
    }

    func testErrorSticksAfterOperationsEnd() {
        var a = SyncActivity()
        a.begin()
        a.noteError("upload failed")
        // In-flight wins the display while the retry runs...
        XCTAssertEqual(a.status, .syncing)
        a.end()
        // ...and the error shows once nothing is in flight.
        XCTAssertEqual(a.status, .error("upload failed"))
    }

    func testSuccessClearsError() {
        var a = SyncActivity()
        a.noteError("fetch failed")
        XCTAssertEqual(a.status, .error("fetch failed"))
        a.noteSuccess()
        XCTAssertEqual(a.status, .idle)
    }
}

final class RemoteUpdatePolicyTests: XCTestCase {
    func testCleanBufferRefreshes() {
        let action = RemoteUpdatePolicy.action(
            bufferContent: "hello", bufferLocation: "Amsterdam",
            persistedContent: "hello", persistedLocation: "Amsterdam")
        XCTAssertEqual(action, .refresh)
    }

    func testDirtyContentNotices() {
        let action = RemoteUpdatePolicy.action(
            bufferContent: "hello there", bufferLocation: nil,
            persistedContent: "hello", persistedLocation: nil)
        XCTAssertEqual(action, .notice)
    }

    func testDirtyLocationNotices() {
        let action = RemoteUpdatePolicy.action(
            bufferContent: "hello", bufferLocation: "Utrecht",
            persistedContent: "hello", persistedLocation: "Amsterdam")
        XCTAssertEqual(action, .notice)
    }

    func testNilAndEmptyLocationAreEquivalent() {
        // The location field round-trips "" while the store holds NULL;
        // that difference must not count as dirty.
        let action = RemoteUpdatePolicy.action(
            bufferContent: "hello", bufferLocation: "",
            persistedContent: "hello", persistedLocation: nil)
        XCTAssertEqual(action, .refresh)
    }

    func testEmptyBufferOverEmptyPersistedRefreshes() {
        // Untouched brand-new day: a remote entry arriving must land.
        let action = RemoteUpdatePolicy.action(
            bufferContent: "", bufferLocation: nil,
            persistedContent: "", persistedLocation: nil)
        XCTAssertEqual(action, .refresh)
    }
}
