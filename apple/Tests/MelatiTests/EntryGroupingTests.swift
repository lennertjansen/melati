import XCTest

/// The entries list renders exclusively through monthGroups (there is no flat
/// mode); these pin its contract: bucket by "yyyy-MM", preserve store order.
final class EntryGroupingTests: XCTestCase {
    private func summary(_ date: String) -> EntrySummary {
        EntrySummary(date: date, preview: "", createdAt: nil, location: nil)
    }

    func testGroupsByMonthPreservingOrder() {
        let groups = EntryUtil.monthGroups([
            summary("2026-08-21"),
            summary("2026-08-03"),
            summary("2026-06-30"),
            summary("2025-12-31"),
        ])
        XCTAssertEqual(groups.map(\.month), ["2026-08", "2026-06", "2025-12"])
        XCTAssertEqual(groups[0].entries.map(\.date), ["2026-08-21", "2026-08-03"])
        XCTAssertEqual(groups[1].entries.map(\.date), ["2026-06-30"])
        XCTAssertEqual(groups[2].entries.map(\.date), ["2025-12-31"])
    }

    func testMonthsWithoutEntriesProduceNoGroup() {
        // A gap (2026-07 here) must not surface as an empty header.
        let groups = EntryUtil.monthGroups([
            summary("2026-08-01"),
            summary("2026-06-15"),
        ])
        XCTAssertEqual(groups.map(\.month), ["2026-08", "2026-06"])
        XCTAssertTrue(groups.allSatisfy { !$0.entries.isEmpty })
    }

    func testEmptyInputYieldsNoGroups() {
        XCTAssertEqual(EntryUtil.monthGroups([]), [])
    }

    func testYearBoundarySplitsGroups() {
        let groups = EntryUtil.monthGroups([
            summary("2026-01-01"),
            summary("2025-12-31"),
        ])
        XCTAssertEqual(groups.map(\.month), ["2026-01", "2025-12"])
    }
}
