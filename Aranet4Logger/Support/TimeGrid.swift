import Foundation

/// Snaps reconstructed/imported timestamps onto the device's logging-interval grid.
///
/// History timestamps downloaded over BLE are *reconstructed* as `now - secondsSinceUpdate -
/// k·interval`, so they carry a small (sub-second to ~1 s) offset that differs between syncs.
/// Storing them raw would give the same physical reading a different primary key each sync,
/// defeating `INSERT OR IGNORE` deduplication. Snapping to the interval grid (which is far
/// larger than the jitter — 60 s or 300 s here) yields a stable key, and makes BLE data and
/// official-app CSV exports line up on the same instants so they merge cleanly.
enum TimeGrid {
    static func snap(_ date: Date, intervalSeconds: Int) -> Date {
        guard intervalSeconds > 0 else {
            return Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded())
        }
        let t = date.timeIntervalSince1970
        let snapped = (t / Double(intervalSeconds)).rounded() * Double(intervalSeconds)
        return Date(timeIntervalSince1970: snapped)
    }
}
