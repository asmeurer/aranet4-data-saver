import Foundation

/// Imports historical data exported from the official Aranet Home app into the database.
///
/// Export format (one device per file):
///   Time(MM/DD/YYYY h:mm:ss A),Carbon dioxide(ppm),Temperature(°F),Relative humidity(%),Atmospheric pressure(hPa)
///   "03/28/2026 12:08:03 PM","506","75.7","22","846.0"
///
/// Notes:
/// - Times are LOCAL time (no offset in the rows; the filename carries the export offset).
/// - Temperature is in °F and is converted to °C to match BLE-collected data.
/// - Timestamps are snapped to the inferred logging-interval grid so imported rows dedup
///   against (and merge with) BLE-collected rows via `INSERT OR IGNORE`.
enum CSVImporter {

    struct Result {
        var parsed: Int
        var inserted: Int
        var intervalSeconds: Int
        var first: Date?
        var last: Date?
    }

    enum ImportError: Error, CustomStringConvertible {
        case unreadable(String)
        case noRows

        var description: String {
            switch self {
            case .unreadable(let m): return "Could not read CSV: \(m)"
            case .noRows: return "No data rows found in CSV"
            }
        }
    }

    private static func makeFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current   // export rows are in local time
        f.dateFormat = "MM/dd/yyyy h:mm:ss a"
        return f
    }

    /// Parse the file into (date, reading-without-deviceID) tuples plus inferred interval.
    static func parse(contentsOf url: URL) throws -> (rows: [(Date, Int?, Double?, Double?, Double?)], interval: Int) {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ImportError.unreadable("\(error)")
        }
        let formatter = makeFormatter()
        var rows: [(Date, Int?, Double?, Double?, Double?)] = []

        var isFirstLine = true
        text.enumerateLines { line, _ in
            if isFirstLine { isFirstLine = false; return }   // header
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return }
            // Fields are quoted and contain no embedded commas, so strip quotes and split.
            let fields = trimmed.replacingOccurrences(of: "\"", with: "").components(separatedBy: ",")
            guard fields.count >= 5, let date = formatter.date(from: fields[0]) else { return }

            let co2 = Int(fields[1])
            let tempF = Double(fields[2])
            let tempC = tempF.map { ($0 - 32.0) * 5.0 / 9.0 }
            let humidity = Double(fields[3])
            let pressure = Double(fields[4])
            rows.append((date, co2, tempC.map { ($0 * 100).rounded() / 100 }, humidity, pressure))
        }

        guard !rows.isEmpty else { throw ImportError.noRows }
        rows.sort { $0.0 < $1.0 }
        return (rows, inferInterval(rows.map { $0.0 }))
    }

    /// Most common spacing (seconds) between consecutive recent samples.
    static func inferInterval(_ dates: [Date]) -> Int {
        guard dates.count >= 2 else { return 0 }
        let recent = dates.suffix(500)
        var counts: [Int: Int] = [:]
        var prev: Date?
        for d in recent {
            if let p = prev {
                let delta = Int(d.timeIntervalSince(p).rounded())
                if delta > 0 { counts[delta, default: 0] += 1 }
            }
            prev = d
        }
        return counts.max { $0.value < $1.value }?.key ?? 0
    }

    /// Import a CSV file for a given device id into the database.
    static func `import`(url: URL, deviceID: String, database: Database) async throws -> Result {
        let (rows, interval) = try parse(contentsOf: url)
        let readings = rows.map { (date, co2, temp, humi, pres) in
            Reading(
                deviceID: deviceID,
                timestamp: TimeGrid.snap(date, intervalSeconds: interval),
                co2: co2,
                temperature: temp,
                humidity: humi,
                pressure: pres
            )
        }
        let inserted = try await database.insert(readings)
        return Result(
            parsed: rows.count,
            inserted: inserted,
            intervalSeconds: interval,
            first: rows.first?.0,
            last: rows.last?.0
        )
    }
}
