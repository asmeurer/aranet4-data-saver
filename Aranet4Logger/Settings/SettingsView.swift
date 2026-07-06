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
    @AppStorage(SettingsKeys.co2Threshold) private var co2Threshold = SettingsKeys.defaultCO2Threshold
    @AppStorage(SettingsKeys.co2MenuBarWarning) private var co2MenuBarWarning = true
    @AppStorage(SettingsKeys.co2Notifications) private var co2Notifications = false
    /// The user enabled notifications but macOS permission is denied.
    @State private var notificationsDenied = false
    /// Suppresses the onChange handler while the code (not the user) reverts the toggle.
    @State private var revertingNotificationsToggle = false
    private var co2ThresholdBinding: Binding<Int> {
        Binding(
            get: { SettingsKeys.clampedCO2Threshold(co2Threshold) },
            set: { co2Threshold = SettingsKeys.clampedCO2Threshold($0) }
        )
    }

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

            Section("CO₂ Alerts") {
                HStack {
                    Text("Warn above")
                    Spacer()
                    TextField("ppm", value: co2ThresholdBinding, format: .number.grouping(.never))
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                    Stepper(
                        "Threshold",
                        value: co2ThresholdBinding,
                        in: SettingsKeys.co2ThresholdRange,
                        step: 100
                    )
                        .labelsHidden()
                    Text("ppm")
                        .foregroundStyle(.secondary)
                }
                Toggle("Show ⚠️ in the menu bar", isOn: $co2MenuBarWarning)
                Toggle("Send a notification", isOn: $co2Notifications)
                if notificationsDenied {
                    Text("Notifications are turned off for Aranet4 Logger in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .background(WindowCapture(.settings))
        .onAppear {
            // Resolve the default/stale device selection to a concrete device so the picker
            // shows a valid choice. The menu bar falls back to the first device regardless.
            if !appState.devices.contains(where: { $0.id == menuBarDeviceID }) {
                menuBarDeviceID = appState.devices.first?.id ?? ""
            }
            co2Threshold = SettingsKeys.clampedCO2Threshold(co2Threshold)
        }
        .onChange(of: co2Notifications) { _, enabled in
            if revertingNotificationsToggle {
                revertingNotificationsToggle = false
                return
            }
            guard enabled else {
                notificationsDenied = false
                return
            }
            Task {
                let granted = await Notifier.shared.requestAuthorization()
                notificationsDenied = !granted
                if !granted {
                    revertingNotificationsToggle = true
                    co2Notifications = false
                }
            }
        }
    }
}

/// UserDefaults keys shared between the settings UI, the menu display, and the Coordinator.
enum SettingsKeys {
    static let temperatureUnit = "temperatureUnit"
    static let pressureUnit = "pressureUnit"
    static let menuBarMetric = "menuBarMetric"
    static let menuBarDeviceID = "menuBarDeviceID"
    static let co2Threshold = "co2Threshold"
    static let co2MenuBarWarning = "co2MenuBarWarning"
    static let co2Notifications = "co2Notifications"

    /// Default high-CO₂ threshold (ppm) — the start of Aranet's red zone.
    static let defaultCO2Threshold = 1400
    static let co2ThresholdRange = 500...5000

    static func clampedCO2Threshold(_ value: Int) -> Int {
        min(max(value, co2ThresholdRange.lowerBound), co2ThresholdRange.upperBound)
    }
}
