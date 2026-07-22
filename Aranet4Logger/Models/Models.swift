import Foundation

/// A single stored sensor reading (one row in the `readings` table).
struct Reading: Sendable {
    var deviceID: String
    var timestamp: Date
    var co2: Int?
    var temperature: Double?
    var humidity: Double?
    var pressure: Double?
}

/// One configured device.
struct DeviceConfig: Codable, Identifiable, Sendable, Equatable {
    /// CoreBluetooth peripheral identifier (a UUID string on macOS).
    var id: String
    /// Friendly name shown in the menu.
    var name: String

    enum CodingKeys: String, CodingKey {
        case id = "address"
        case name
    }
}

/// Top-level app configuration, persisted as JSON in Application Support.
struct AppConfig: Codable, Sendable {
    var devices: [DeviceConfig]
    /// Device IDs the user removed in Settings; the BLE scan won't re-add these.
    var ignoredDevices: [String]
    var pollInterval: Double        // seconds between history syncs per device
    var connectTimeout: Double      // seconds per connection attempt
    var connectRetries: Int         // attempts per sync before giving up this cycle
    var retryBackoff: Double        // base backoff seconds (escalates per attempt)

    init(
        devices: [DeviceConfig],
        ignoredDevices: [String] = [],
        pollInterval: Double,
        connectTimeout: Double,
        connectRetries: Int,
        retryBackoff: Double
    ) {
        self.devices = devices
        self.ignoredDevices = ignoredDevices
        self.pollInterval = pollInterval
        self.connectTimeout = connectTimeout
        self.connectRetries = connectRetries
        self.retryBackoff = retryBackoff
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        devices = try c.decode([DeviceConfig].self, forKey: .devices)
        // Missing in configs written before device removal existed.
        ignoredDevices = try c.decodeIfPresent([String].self, forKey: .ignoredDevices) ?? []
        pollInterval = try c.decode(Double.self, forKey: .pollInterval)
        connectTimeout = try c.decode(Double.self, forKey: .connectTimeout)
        connectRetries = try c.decode(Int.self, forKey: .connectRetries)
        retryBackoff = try c.decode(Double.self, forKey: .retryBackoff)
    }

    static let `default` = AppConfig(
        // Devices are discovered from the BLE scan and appended here (see
        // Coordinator.addDiscoveredDevice); none are hardcoded.
        devices: [],
        pollInterval: 600,
        connectTimeout: 30,
        connectRetries: 5,
        retryBackoff: 10
    )
}
