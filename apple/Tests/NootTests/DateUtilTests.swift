import XCTest

final class DateUtilTests: XCTestCase {
    func testFormatSyncTimestampParsesFractionalSeconds() {
        let out = DateUtil.formatSyncTimestamp("2026-08-04T10:15:30.123Z")
        XCTAssertNotEqual(out, "2026-08-04T10:15:30.123Z")
        XCTAssertFalse(out.isEmpty)
    }

    func testFormatSyncTimestampParsesPlainISO() {
        let out = DateUtil.formatSyncTimestamp("2026-08-04T10:15:30Z")
        XCTAssertNotEqual(out, "2026-08-04T10:15:30Z")
        XCTAssertFalse(out.isEmpty)
    }

    func testFormatSyncTimestampFallsBackToRawOnGarbage() {
        XCTAssertEqual(DateUtil.formatSyncTimestamp("not-a-date"), "not-a-date")
    }
}
