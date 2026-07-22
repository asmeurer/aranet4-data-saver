import Foundation
import SQLite3

/// One aggregated point for charting: per-bucket averages of the stored readings. A metric
/// is `nil` when no reading in the bucket carried it.
struct HistoryPoint: Sendable, Equatable {
    /// Start of the aggregation bucket (UTC).
    var timestamp: Date
    var co2: Double?
    var temperature: Double?
    var humidity: Double?
    var pressure: Double?
}

/// One stored battery sample. Rows are only written when the level changes, so each point
/// marks the moment a device first reported that percentage.
struct BatteryPoint: Sendable, Equatable {
    var timestamp: Date
    var battery: Int
}

/// Thread-safe SQLite store for readings, using the system libsqlite3 directly (no
/// third-party dependency). Deduplication is handled by a composite primary key plus
/// `INSERT OR IGNORE`, so re-downloaded history is absorbed for free.
///
/// An `actor` serializes all access, so a single connection is safe across concurrent
/// collectors.
actor Database {
    private var db: OpaquePointer?

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Open (or create) the database. Defaults to the app's database in Application Support;
    /// tests pass a temporary path.
    init(path: String = AppPaths.database.path) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            throw DBError.open(message: "Could not open database at \(path)")
        }
        db = handle
        try Database.execRaw(handle, "PRAGMA journal_mode=WAL;")
        try Database.execRaw(handle, "PRAGMA busy_timeout=5000;")
        try Database.execRaw(handle, """
            CREATE TABLE IF NOT EXISTS readings (
                device TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                co2 INTEGER,
                temperature REAL,
                humidity REAL,
                pressure REAL,
                PRIMARY KEY (device, timestamp)
            );
            """)
        try Database.execRaw(handle, """
            CREATE TABLE IF NOT EXISTS battery_history (
                device TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                battery INTEGER NOT NULL,
                PRIMARY KEY (device, timestamp)
            );
            """)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    enum DBError: Error, CustomStringConvertible {
        case open(message: String)
        case prepare(message: String)
        case step(message: String)

        var description: String {
            switch self {
            case .open(let m), .prepare(let m), .step(let m): return m
            }
        }
    }

    /// Execute a statement on a raw db handle. `nonisolated static` so it can be called from
    /// the synchronous initializer without actor-isolation warnings.
    nonisolated private static func execRaw(_ db: OpaquePointer?, _ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errmsg) != SQLITE_OK {
            let message = errmsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errmsg)
            throw DBError.step(message: "exec failed: \(message)")
        }
    }

    private func exec(_ sql: String) throws {
        try Database.execRaw(db, sql)
    }

    /// Insert readings, ignoring any whose (device, timestamp) already exists.
    /// Returns the number of newly inserted rows.
    func insert(_ readings: [Reading]) throws -> Int {
        guard !readings.isEmpty else { return 0 }
        try exec("BEGIN IMMEDIATE TRANSACTION;")
        var inserted = 0
        do {
            let sql = """
                INSERT OR IGNORE INTO readings (device, timestamp, co2, temperature, humidity, pressure)
                VALUES (?, ?, ?, ?, ?, ?);
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DBError.prepare(message: "prepare insert: \(lastErrorMessage())")
            }
            defer { sqlite3_finalize(stmt) }

            for r in readings {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                bindText(stmt, 1, r.deviceID)
                bindText(stmt, 2, isoFormatter.string(from: r.timestamp))
                bindInt(stmt, 3, r.co2)
                bindDouble(stmt, 4, r.temperature)
                bindDouble(stmt, 5, r.humidity)
                bindDouble(stmt, 6, r.pressure)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw DBError.step(message: "insert step: \(lastErrorMessage())")
                }
                inserted += sqlite3_changes(db) > 0 ? 1 : 0
            }
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
        return inserted
    }

    /// Most recent stored timestamp for a device, used to bound incremental history downloads.
    func lastTimestamp(device: String) throws -> Date? {
        let sql = "SELECT MAX(timestamp) FROM readings WHERE device = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare(message: "prepare lastTimestamp: \(lastErrorMessage())")
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, device)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard sqlite3_column_type(stmt, 0) != SQLITE_NULL,
              let cString = sqlite3_column_text(stmt, 0) else { return nil }
        return isoFormatter.date(from: String(cString: cString))
    }

    /// Oldest stored timestamp for a device, used to size the "All" chart range.
    func firstTimestamp(device: String) throws -> Date? {
        let sql = "SELECT MIN(timestamp) FROM readings WHERE device = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare(message: "prepare firstTimestamp: \(lastErrorMessage())")
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, device)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard sqlite3_column_type(stmt, 0) != SQLITE_NULL,
              let cString = sqlite3_column_text(stmt, 0) else { return nil }
        return isoFormatter.date(from: String(cString: cString))
    }

    /// Bucketed history for charting: readings for a device grouped into `bucketSeconds`-wide
    /// buckets (aligned to the Unix epoch), averaging each metric within a bucket. Aggregating
    /// in SQL keeps a months-long range down to a few hundred points per series. Ordered by
    /// time; `from`/`to` (both inclusive) bound the range, or pass `nil` for no bound.
    func history(
        device: String, from: Date?, to: Date? = nil, bucketSeconds: Int
    ) throws -> [HistoryPoint] {
        precondition(bucketSeconds > 0, "bucketSeconds must be positive")
        var sql = """
            SELECT (CAST(strftime('%s', timestamp) AS INTEGER) / ?2) * ?2 AS bucket,
                   AVG(co2), AVG(temperature), AVG(humidity), AVG(pressure)
            FROM readings
            WHERE device = ?1
            """
        if from != nil { sql += " AND timestamp >= ?3" }
        if to != nil { sql += " AND timestamp <= ?4" }
        sql += " GROUP BY bucket ORDER BY bucket;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare(message: "prepare history: \(lastErrorMessage())")
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, device)
        sqlite3_bind_int64(stmt, 2, Int64(bucketSeconds))
        if let from { bindText(stmt, 3, isoFormatter.string(from: from)) }
        if let to { bindText(stmt, 4, isoFormatter.string(from: to)) }

        var points: [HistoryPoint] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else {
                throw DBError.step(message: "history step: \(lastErrorMessage())")
            }
            points.append(HistoryPoint(
                timestamp: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 0))),
                co2: columnDouble(stmt, 1),
                temperature: columnDouble(stmt, 2),
                humidity: columnDouble(stmt, 3),
                pressure: columnDouble(stmt, 4)
            ))
        }
        return points
    }

    /// Record a battery sample, but only when it differs from the device's most recent stored
    /// level — the battery drains over months, so change-only rows keep the table at roughly
    /// one row per percentage point while still timestamping every drop.
    /// Returns true if a row was written.
    @discardableResult
    func recordBattery(device: String, battery: Int, at timestamp: Date) throws -> Bool {
        let sql = """
            INSERT OR IGNORE INTO battery_history (device, timestamp, battery)
            SELECT ?1, ?2, ?3
            WHERE COALESCE(
                (SELECT battery FROM battery_history WHERE device = ?1
                 ORDER BY timestamp DESC LIMIT 1),
                -1
            ) != ?3;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare(message: "prepare recordBattery: \(lastErrorMessage())")
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, device)
        bindText(stmt, 2, isoFormatter.string(from: timestamp))
        sqlite3_bind_int64(stmt, 3, Int64(battery))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DBError.step(message: "recordBattery step: \(lastErrorMessage())")
        }
        return sqlite3_changes(db) > 0
    }

    /// Stored battery samples for a device, ordered by time. `from`/`to` (both inclusive)
    /// bound the range, or pass `nil` for no bound.
    func batteryHistory(device: String, from: Date? = nil, to: Date? = nil) throws -> [BatteryPoint] {
        var sql = "SELECT timestamp, battery FROM battery_history WHERE device = ?1"
        if from != nil { sql += " AND timestamp >= ?2" }
        if to != nil { sql += " AND timestamp <= ?3" }
        sql += " ORDER BY timestamp;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare(message: "prepare batteryHistory: \(lastErrorMessage())")
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, device)
        if let from { bindText(stmt, 2, isoFormatter.string(from: from)) }
        if let to { bindText(stmt, 3, isoFormatter.string(from: to)) }

        var points: [BatteryPoint] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else {
                throw DBError.step(message: "batteryHistory step: \(lastErrorMessage())")
            }
            guard let cString = sqlite3_column_text(stmt, 0),
                  let date = isoFormatter.date(from: String(cString: cString)) else { continue }
            points.append(BatteryPoint(timestamp: date, battery: Int(sqlite3_column_int64(stmt, 1))))
        }
        return points
    }

    /// Number of stored rows for a device (shown in the menu).
    func count(device: String) throws -> Int {
        let sql = "SELECT COUNT(*) FROM readings WHERE device = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare(message: "prepare count: \(lastErrorMessage())")
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, device)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - Binding helpers

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, Database.SQLITE_TRANSIENT)
    }

    private func bindInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value { sqlite3_bind_int64(stmt, index, Int64(value)) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private func bindDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value { sqlite3_bind_double(stmt, index, value) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private func columnDouble(_ stmt: OpaquePointer?, _ index: Int32) -> Double? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, index)
    }

    private func lastErrorMessage() -> String {
        if let cString = sqlite3_errmsg(db) { return String(cString: cString) }
        return "unknown"
    }
}
