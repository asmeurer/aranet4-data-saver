import Foundation
import XCTest

final class CSVImporterTests: XCTestCase {
    private let sampleCSV = """
    Time(MM/DD/YYYY h:mm:ss A),Carbon dioxide(ppm),Temperature(°F),Relative humidity(%),Atmospheric pressure(hPa)
    "03/28/2026 12:08:03 PM","506","75.7","22","846.0"
    "03/28/2026 12:13:03 PM","501","75.7","22","845.8"
    "03/28/2026 12:18:03 PM","510","75.9","23","845.9"
    """

    private func writeTempCSV(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aranet-test-\(UUID().uuidString).csv")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTempDatabase() throws -> Database {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("aranet-test-\(UUID().uuidString).sqlite").path
        return try Database(path: path)
    }

    func testParseConvertsFahrenheitAndInfersInterval() throws {
        let url = try writeTempCSV(sampleCSV)
        defer { try? FileManager.default.removeItem(at: url) }

        let (rows, interval) = try CSVImporter.parse(contentsOf: url)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(interval, 300)  // 5-minute spacing inferred

        // 75.7 °F == 24.28 °C (rounded to 2 places).
        XCTAssertEqual(rows[0].temperature ?? 0, 24.28, accuracy: 0.01)
        XCTAssertEqual(rows[0].co2, 506)
        XCTAssertEqual(rows[0].humidity, 22)
        XCTAssertEqual(rows[0].pressure ?? 0, 846.0, accuracy: 0.001)

        // Rows are sorted ascending by time.
        XCTAssertLessThan(rows[0].date, rows[1].date)
    }

    func testImportInsertsThenDedups() async throws {
        let url = try writeTempCSV(sampleCSV)
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try makeTempDatabase()

        let first = try await CSVImporter.import(url: url, deviceID: "DEV-A", database: db)
        XCTAssertEqual(first.parsed, 3)
        XCTAssertEqual(first.inserted, 3)

        // Re-importing the same file inserts nothing (dedup via INSERT OR IGNORE).
        let second = try await CSVImporter.import(url: url, deviceID: "DEV-A", database: db)
        XCTAssertEqual(second.parsed, 3)
        XCTAssertEqual(second.inserted, 0)

        let count = try await db.count(device: "DEV-A")
        XCTAssertEqual(count, 3)
    }

    func testParseEmptyThrows() throws {
        let header = "Time,CO2,Temp,Humidity,Pressure"
        let url = try writeTempCSV(header)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try CSVImporter.parse(contentsOf: url))
    }
}
