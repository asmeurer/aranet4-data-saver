import Foundation
import XCTest

final class DatabaseTests: XCTestCase {
    private func makeTempDatabase() throws -> Database {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("aranet-test-\(UUID().uuidString).sqlite").path
        return try Database(path: path)
    }

    func testInsertAndDedup() async throws {
        let db = try makeTempDatabase()
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_300)
        let readings = [
            Reading(deviceID: "DEV-A", timestamp: t1, co2: 600, temperature: 22.5, humidity: 40, pressure: 840),
            Reading(deviceID: "DEV-A", timestamp: t2, co2: 610, temperature: 22.6, humidity: 41, pressure: 841),
        ]

        let inserted = try await db.insert(readings)
        XCTAssertEqual(inserted, 2)

        // Same (device, timestamp) keys are ignored on re-insert.
        let again = try await db.insert(readings)
        XCTAssertEqual(again, 0)

        let count = try await db.count(device: "DEV-A")
        XCTAssertEqual(count, 2)
    }

    func testLastTimestamp() async throws {
        let db = try makeTempDatabase()
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_300)
        _ = try await db.insert([
            Reading(deviceID: "DEV-A", timestamp: t1, co2: nil, temperature: nil, humidity: nil, pressure: nil),
            Reading(deviceID: "DEV-A", timestamp: t2, co2: nil, temperature: nil, humidity: nil, pressure: nil),
        ])

        let last = try await db.lastTimestamp(device: "DEV-A")
        XCTAssertEqual(last?.timeIntervalSince1970 ?? 0, t2.timeIntervalSince1970, accuracy: 0.001)
        let missing = try await db.lastTimestamp(device: "MISSING")
        XCTAssertNil(missing)
    }

    func testPerDeviceIsolation() async throws {
        let db = try makeTempDatabase()
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await db.insert([
            Reading(deviceID: "DEV-A", timestamp: t1, co2: 1, temperature: nil, humidity: nil, pressure: nil),
            Reading(deviceID: "DEV-B", timestamp: t1, co2: 2, temperature: nil, humidity: nil, pressure: nil),
        ])
        let countA = try await db.count(device: "DEV-A")
        let countB = try await db.count(device: "DEV-B")
        XCTAssertEqual(countA, 1)
        XCTAssertEqual(countB, 1)
    }
}
