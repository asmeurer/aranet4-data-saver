import Foundation
import Observation

/// Sync status for one device, shown in the menu.
enum DeviceStatus: Equatable {
    case idle
    case syncing
    case ok
    case retrying(attempt: Int)
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .syncing: return "Syncing…"
        case .ok: return "OK"
        case .retrying(let n): return "Retrying (\(n))…"
        case .failed(let m): return "Failed: \(m)"
        }
    }
}

/// Per-device display state, combining live advertisement data and sync results.
@Observable
final class DeviceState: Identifiable {
    let id: String
    var name: String
    var co2: Int?
    var temperature: Double?
    var humidity: Double?
    var pressure: Double?
    var battery: Int?
    var rssi: Int?
    var lastSeen: Date?        // last advertisement
    var lastSync: Date?        // last successful history sync
    var storedCount: Int = 0
    var status: DeviceStatus = .idle

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    var batteryIsLow: Bool { (battery ?? 100) <= 20 }
    var isStale: Bool {
        guard let lastSync else { return true }
        return Date().timeIntervalSince(lastSync) > 3600
    }
}

/// Global observable state driving the menu bar UI. Updated only on the main actor.
@MainActor
@Observable
final class AppState {
    var devices: [DeviceState] = []
    var bluetoothReady = false
    var launchAtLogin = false

    func device(_ id: String) -> DeviceState? {
        devices.first { $0.id == id }
    }

    /// Worst-case status glyph for the menu bar title.
    var statusSymbol: String {
        if devices.contains(where: { if case .failed = $0.status { return true } else { return false } }) {
            return "exclamationmark.triangle.fill"
        }
        if devices.contains(where: { $0.batteryIsLow || $0.isStale }) {
            return "exclamationmark.triangle"
        }
        return "carbon.dioxide.cloud.fill"
    }
}
