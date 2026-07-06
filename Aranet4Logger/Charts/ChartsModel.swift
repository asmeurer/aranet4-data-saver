import Foundation
import Observation

/// Loads bucketed history from the database for the Charts window. One instance lives for
/// the app's lifetime (the window binds to it), so the selected range and hidden devices
/// survive closing and reopening the window.
@MainActor
@Observable
final class ChartsModel {
    /// One device's fetched history plus its fixed palette slot.
    struct DeviceSeries: Identifiable {
        let id: String
        let name: String
        /// Palette slot, from the device's position in the config — stable across filtering.
        let slot: Int
        let points: [HistoryPoint]
    }

    let appState: AppState
    private let database: Database?

    var range: ChartTimeRange = .day {
        didSet { reload() }
    }
    /// Devices toggled off in the legend row. They keep their color slot while hidden.
    var hiddenDeviceIDs: Set<String> = []
    private(set) var series: [DeviceSeries] = []
    /// Bucket width of the current `series`, used to break lines across data gaps.
    private(set) var bucketSeconds: Int = 300
    private(set) var errorMessage: String?

    /// Invalidates stale loads: only the newest reload may publish results.
    private var loadGeneration = 0

    init(appState: AppState, database: Database?) {
        self.appState = appState
        self.database = database
        #if DEBUG
        // Test hook: preselect a range at launch, for scripted UI screenshots.
        if let raw = ProcessInfo.processInfo.environment["ARANET4_CHARTS_RANGE"],
           let preset = ChartTimeRange(rawValue: raw) {
            range = preset
        }
        #endif
    }

    var visibleSeries: [DeviceSeries] {
        series.filter { !hiddenDeviceIDs.contains($0.id) }
    }

    /// A line may bridge one missing bucket (a single dropped sample); longer gaps break it.
    var maxGap: TimeInterval { TimeInterval(2 * bucketSeconds) }

    func toggleVisibility(_ deviceID: String) {
        if hiddenDeviceIDs.contains(deviceID) {
            hiddenDeviceIDs.remove(deviceID)
        } else {
            hiddenDeviceIDs.insert(deviceID)
        }
    }

    func reload() {
        guard let database else {
            errorMessage = "Database is unavailable — see aranet.log."
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        let devices = appState.devices.enumerated().map { (slot: $0, id: $1.id, name: $1.name) }
        let range = range

        Task {
            do {
                let now = Date()
                var from: Date?
                var span: TimeInterval
                if let duration = range.duration {
                    from = now.addingTimeInterval(-duration)
                    span = duration
                } else {
                    // Full history: size the buckets from the oldest stored reading.
                    var earliest = now
                    for device in devices {
                        if let first = try await database.firstTimestamp(device: device.id) {
                            earliest = min(earliest, first)
                        }
                    }
                    span = max(now.timeIntervalSince(earliest), 86_400)
                }
                let bucket = ChartTimeRange.bucketSeconds(spanning: span)

                var loaded: [DeviceSeries] = []
                for device in devices {
                    let points = try await database.history(
                        device: device.id, from: from, bucketSeconds: bucket
                    )
                    loaded.append(DeviceSeries(
                        id: device.id, name: device.name, slot: device.slot, points: points
                    ))
                }

                guard generation == loadGeneration else { return }
                bucketSeconds = bucket
                series = loaded
                errorMessage = nil
            } catch {
                AppLog.shared.error("Chart history query failed: \(error)")
                guard generation == loadGeneration else { return }
                errorMessage = "\(error)"
            }
        }
    }
}
