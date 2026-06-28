import SwiftUI

/// The app's Settings window (opened from the menu or ⌘,). Configures display units and which
/// reading (if any) is shown directly in the menu bar.
struct SettingsView: View {
    /// Live device state. Devices are discovered from the BLE scan; their names are editable
    /// here (the Aranet sensors only report their factory "Aranet4 XXXXX" name over Bluetooth —
    /// the custom names set in the Aranet app are not exposed to other BLE clients).
    var appState: AppState
    /// Persist a renamed device.
    var onRename: (_ id: String, _ name: String) -> Void

    @AppStorage(SettingsKeys.temperatureUnit) private var temperatureUnit = TemperatureUnit.localeDefault
    @AppStorage(SettingsKeys.pressureUnit) private var pressureUnit = PressureUnit.localeDefault
    @AppStorage(SettingsKeys.menuBarMetric) private var menuBarMetric = MenuBarMetric.co2
    @AppStorage(SettingsKeys.menuBarDeviceID) private var menuBarDeviceID = ""

    var body: some View {
        Form {
            Section("Devices") {
                if appState.devices.isEmpty {
                    Text("No devices yet — sensors are added automatically as they're seen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(appState.devices) { device in
                    TextField("Name", text: Binding(
                        get: { device.name },
                        set: { onRename(device.id, $0) }
                    ))
                }
            }

            Section("Menu Bar") {
                Picker("Show reading", selection: $menuBarMetric) {
                    ForEach(MenuBarMetric.allCases) { Text($0.label).tag($0) }
                }
                if menuBarMetric != .none {
                    Picker("Sensor", selection: $menuBarDeviceID) {
                        ForEach(appState.devices) { Text($0.name).tag($0.id) }
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
        .background(SettingsWindowCapture())
        .onAppear {
            // Resolve the default/stale device selection to a concrete device so the picker
            // shows a valid choice. The menu bar falls back to the first device regardless.
            if !appState.devices.contains(where: { $0.id == menuBarDeviceID }) {
                menuBarDeviceID = appState.devices.first?.id ?? ""
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
