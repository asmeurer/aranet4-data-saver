import Foundation
import XCTest

final class HistoryQueryTests: XCTestCase {
    private func makeTempDatabase() throws -> Database {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("aranet-test-\(UUID().uuidString).sqlite").path
        return try Database(path: path)
    }

    /// A base instant aligned to a 600 s bucket boundary, so expected buckets are exact.
    private let base = Date(timeIntervalSince1970: 1_700_000_400)

    func testHistoryAveragesWithinBuckets() async throws {
        let db = try makeTempDatabase()
        _ = try await db.insert([
            // Bucket 1: two readings → averaged.
            Reading(deviceID: "DEV-A", timestamp: base,
                    co2: 600, temperature: 20, humidity: 40, pressure: 840),
            Reading(deviceID: "DEV-A", timestamp: base.addingTimeInterval(300),
                    co2: 700, temperature: 22, humidity: 42, pressure: 842),
            // Bucket 2: one reading.
            Reading(deviceID: "DEV-A", timestamp: base.addingTimeInterval(600),
                    co2: 800, temperature: 24, humidity: 44, pressure: 844),
        ])

        let points = try await db.history(device: "DEV-A", from: nil, bucketSeconds: 600)
        XCTAssertEqual(points.count, 2)

        XCTAssertEqual(points[0].timestamp, base)
        XCTAssertEqual(points[0].co2, 650)
        XCTAssertEqual(points[0].temperature ?? 0, 21, accuracy: 0.001)
        XCTAssertEqual(points[0].humidity ?? 0, 41, accuracy: 0.001)
        XCTAssertEqual(points[0].pressure ?? 0, 841, accuracy: 0.001)

        XCTAssertEqual(points[1].timestamp, base.addingTimeInterval(600))
        XCTAssertEqual(points[1].co2, 800)
    }

    func testHistoryKeepsMissingMetricsNil() async throws {
        let db = try makeTempDatabase()
        _ = try await db.insert([
            Reading(deviceID: "DEV-A", timestamp: base,
                    co2: 600, temperature: nil, humidity: nil, pressure: nil)
        ])
        let points = try await db.history(device: "DEV-A", from: nil, bucketSeconds: 600)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].co2, 600)
        XCTAssertNil(points[0].temperature)
        XCTAssertNil(points[0].humidity)
        XCTAssertNil(points[0].pressure)
    }

    func testHistoryRespectsFromBoundAndDevice() async throws {
        let db = try makeTempDatabase()
        _ = try await db.insert([
            Reading(deviceID: "DEV-A", timestamp: base,
                    co2: 600, temperature: nil, humidity: nil, pressure: nil),
            Reading(deviceID: "DEV-A", timestamp: base.addingTimeInterval(600),
                    co2: 700, temperature: nil, humidity: nil, pressure: nil),
            Reading(deviceID: "DEV-B", timestamp: base.addingTimeInterval(600),
                    co2: 999, temperature: nil, humidity: nil, pressure: nil),
        ])

        let points = try await db.history(
            device: "DEV-A", from: base.addingTimeInterval(1), bucketSeconds: 600
        )
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].co2, 700)
    }

    func testFirstTimestamp() async throws {
        let db = try makeTempDatabase()
        _ = try await db.insert([
            Reading(deviceID: "DEV-A", timestamp: base.addingTimeInterval(600),
                    co2: nil, temperature: nil, humidity: nil, pressure: nil),
            Reading(deviceID: "DEV-A", timestamp: base,
                    co2: nil, temperature: nil, humidity: nil, pressure: nil),
        ])
        let first = try await db.firstTimestamp(device: "DEV-A")
        XCTAssertEqual(first?.timeIntervalSince1970 ?? 0, base.timeIntervalSince1970, accuracy: 0.001)
        let missing = try await db.firstTimestamp(device: "MISSING")
        XCTAssertNil(missing)
    }
}
