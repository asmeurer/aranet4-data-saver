import Foundation
import XCTest

final class ChartDataTests: XCTestCase {
    // MARK: - Bucket sizing

    func testBucketSnapsToSampleGrid() {
        // A day of 5-minute data is already ~300 points — no aggregation.
        XCTAssertEqual(ChartTimeRange.bucketSeconds(spanning: 86_400), 300)
        // Longer spans aggregate, always in whole 5-minute steps.
        XCTAssertEqual(ChartTimeRange.bucketSeconds(spanning: 3 * 86_400), 900)
        XCTAssertEqual(ChartTimeRange.bucketSeconds(spanning: 7 * 86_400), 2_100)
        XCTAssertEqual(ChartTimeRange.bucketSeconds(spanning: 30 * 86_400), 8_700)
    }

    func testBucketNeverBelowSampleGrid() {
        XCTAssertEqual(ChartTimeRange.bucketSeconds(spanning: 60), 300)
        XCTAssertEqual(ChartTimeRange.bucketSeconds(spanning: 0), 300)
    }

    func testBucketKeepsSeriesNearTargetSize() {
        for days in [1, 3, 7, 30, 90, 365] {
            let span = TimeInterval(days * 86_400)
            let bucket = ChartTimeRange.bucketSeconds(spanning: span)
            let points = span / Double(bucket)
            XCTAssertLessThanOrEqual(points, 300, "\(days)d yields \(points) points")
            XCTAssertGreaterThan(points, 100, "\(days)d yields only \(points) points")
        }
    }

    // MARK: - Gap segmentation

    private func point(_ seconds: TimeInterval, _ value: Double = 1) -> MetricPoint {
        MetricPoint(date: Date(timeIntervalSince1970: seconds), value: value)
    }

    func testSegmentsSplitAtGaps() {
        let points = [point(0), point(300), point(600), point(3_600), point(3_900)]
        let segments = contiguousSegments(of: points, maxGap: 600)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0], [point(0), point(300), point(600)])
        XCTAssertEqual(segments[1], [point(3_600), point(3_900)])
    }

    func testGapExactlyAtLimitDoesNotSplit() {
        let points = [point(0), point(600)]
        XCTAssertEqual(contiguousSegments(of: points, maxGap: 600).count, 1)
    }

    func testSegmentsOfEmptyAndSingle() {
        XCTAssertTrue(contiguousSegments(of: [], maxGap: 600).isEmpty)
        XCTAssertEqual(contiguousSegments(of: [point(0)], maxGap: 600), [[point(0)]])
    }
}
