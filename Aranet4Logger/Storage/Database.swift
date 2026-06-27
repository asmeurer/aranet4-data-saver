import Foundation
import SQLite3

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

    init() throws {
        var handle: OpaquePointer?
        let path = AppPaths.database.path
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

    private func lastErrorMessage() -> String {
        if let cString = sqlite3_errmsg(db) { return String(cString: cString) }
        return "unknown"
    }
}
