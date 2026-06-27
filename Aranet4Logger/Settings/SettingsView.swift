import SwiftUI

/// The app's Settings window (opened from the menu or ⌘,). For now it only configures display
/// units, defaulting from the current locale.
struct SettingsView: View {
    @AppStorage(SettingsKeys.temperatureUnit) private var temperatureUnit = TemperatureUnit.localeDefault
    @AppStorage(SettingsKeys.pressureUnit) private var pressureUnit = PressureUnit.localeDefault

    var body: some View {
        Form {
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
    }
}

/// UserDefaults keys shared between the settings UI and the menu display.
enum SettingsKeys {
    static let temperatureUnit = "temperatureUnit"
    static let pressureUnit = "pressureUnit"
}
