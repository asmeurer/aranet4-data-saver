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
    var pollInterval: Double        // seconds between history syncs per device
    var connectTimeout: Double      // seconds per connection attempt
    var connectRetries: Int         // attempts per sync before giving up this cycle
    var retryBackoff: Double        // base backoff seconds (escalates per attempt)

    static let `default` = AppConfig(
        devices: [
            DeviceConfig(id: "29DEA9EB-B053-A853-8CF0-7B83133FA52C", name: "Aranet4 0AC5A"),
            DeviceConfig(id: "01F2AF95-0F95-EDFF-8D48-3F6E07876F65", name: "Aranet4 06F19"),
        ],
        pollInterval: 600,
        connectTimeout: 30,
        connectRetries: 5,
        retryBackoff: 10
    )
}
