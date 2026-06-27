import SwiftUI

/// The app's Settings window (opened from the menu or ⌘,). Configures display units and which
/// reading (if any) is shown directly in the menu bar.
struct SettingsView: View {
    /// Configured devices, used to choose which sensor feeds the menu bar reading.
    var devices: [(id: String, name: String)]

    @AppStorage(SettingsKeys.temperatureUnit) private var temperatureUnit = TemperatureUnit.localeDefault
    @AppStorage(SettingsKeys.pressureUnit) private var pressureUnit = PressureUnit.localeDefault
    @AppStorage(SettingsKeys.menuBarMetric) private var menuBarMetric = MenuBarMetric.co2
    @AppStorage(SettingsKeys.menuBarDeviceID) private var menuBarDeviceID = ""

    var body: some View {
        Form {
            Section("Menu Bar") {
                Picker("Show reading", selection: $menuBarMetric) {
                    ForEach(MenuBarMetric.allCases) { Text($0.label).tag($0) }
                }
                if menuBarMetric != .none {
                    Picker("Sensor", selection: $menuBarDeviceID) {
                        ForEach(devices, id: \.id) { Text($0.name).tag($0.id) }
                    }
                }
            }

            Section("Units") {
                Picker("Temperature", selection: $temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { Text($0.label).tag($0) }
                }
                Picker("Pressure", selection: $pressureUnit) {
                    ForEach(PressureUnit.allCases) { Text($0.label).tag($0) }
                }
                Text("CO₂ (ppm) and humidity (%) have no alternate units.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .onAppear {
            // Resolve the default/stale device selection to a concrete device so the picker
            // shows a valid choice. The menu bar falls back to the first device regardless.
            if !devices.contains(where: { $0.id == menuBarDeviceID }) {
                menuBarDeviceID = devices.first?.id ?? ""
            }
        }
    }
}

/// UserDefaults keys shared between the settings UI and the menu display.
enum SettingsKeys {
    static let temperatureUnit = "temperatureUnit"
    static let pressureUnit = "pressureUnit"
    static let menuBarMetric = "menuBarMetric"
    static let menuBarDeviceID = "menuBarDeviceID"
}
