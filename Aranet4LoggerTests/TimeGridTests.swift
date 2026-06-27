import Foundation
import XCTest

final class TimeGridTests: XCTestCase {
    func testSnapToNearestInterval() {
        // 12:03:09 should snap to the nearest 300 s (5 min) grid point: 12:05:00.
        let date = Date(timeIntervalSince1970: 12 * 3600 + 3 * 60 + 9)
        let snapped = TimeGrid.snap(date, intervalSeconds: 300)
        XCTAssertEqual(snapped.timeIntervalSince1970, 12 * 3600 + 5 * 60, accuracy: 0.0001)
    }

    func testJitterSnapsToSameGridPoint() {
        // The whole point of snapping: reconstructed timestamps that differ by a couple of
        // seconds must map to the same key so dedup works.
        let base = 1_700_000_000.0
        let a = TimeGrid.snap(Date(timeIntervalSince1970: base + 1), intervalSeconds: 60)
        let b = TimeGrid.snap(Date(timeIntervalSince1970: base - 2), intervalSeconds: 60)
        XCTAssertEqual(a, b)
    }

    func testDistinctReadingsStayDistinct() {
        let a = TimeGrid.snap(Date(timeIntervalSince1970: 1_700_000_000), intervalSeconds: 60)
        let b = TimeGrid.snap(Date(timeIntervalSince1970: 1_700_000_060), intervalSeconds: 60)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(b.timeIntervalSince(a), 60, accuracy: 0.0001)
    }

    func testZeroIntervalRoundsToSecond() {
        let snapped = TimeGrid.snap(Date(timeIntervalSince1970: 100.4), intervalSeconds: 0)
        XCTAssertEqual(snapped.timeIntervalSince1970, 100, accuracy: 0.0001)
    }
}
