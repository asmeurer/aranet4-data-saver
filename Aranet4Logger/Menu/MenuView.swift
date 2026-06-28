import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The menu bar title: either the plain status icon, or a selected sensor reading as text
/// (prefixed with a warning glyph when a device has failed, is stale, or has a low battery).
struct MenuBarLabel: View {
    var appState: AppState

    @AppStorage(SettingsKeys.menuBarMetric) private var menuBarMetric = MenuBarMetric.co2
    @AppStorage(SettingsKeys.menuBarDeviceID) private var menuBarDeviceID = ""
    @AppStorage(SettingsKeys.temperatureUnit) private var temperatureUnit = TemperatureUnit.localeDefault
    @AppStorage(SettingsKeys.pressureUnit) private var pressureUnit = PressureUnit.localeDefault

    var body: some View {
        if menuBarMetric == .none {
            Image(systemName: appState.statusSymbol)
        } else if let reading = readingText {
            Text(warningPrefix + reading)
        } else {
            // Metric selected but no value yet — fall back to the status icon.
            Image(systemName: appState.statusSymbol)
        }
    }

    /// The chosen device, falling back to the first configured device.
    private var device: DeviceState? {
        appState.device(menuBarDeviceID) ?? appState.devices.first
    }

    private var warningPrefix: String {
        appState.hasFailure || appState.hasWarning ? "⚠️ " : ""
    }

    private var readingText: String? {
        guard let device else { return nil }
        return menuBarMetric.menuBarText(
            co2: device.co2,
            temperature: device.temperature,
            humidity: device.humidity,
            pressure: device.pressure,
            temperatureUnit: temperatureUnit,
            pressureUnit: pressureUnit
        )
    }
}

/// The dropdown content of the menu bar item.
struct MenuView: View {
    var appState: AppState
    var onSyncNow: () -> Void
    var onToggleLogin: (Bool) -> Void
    /// Import action for an Aranet CSV export targeting a specific device.
    var onImportCSV: (_ deviceID: String, _ url: URL) -> Void

    @AppStorage(SettingsKeys.temperatureUnit) private var temperatureUnit = TemperatureUnit.localeDefault
    @AppStorage(SettingsKeys.pressureUnit) private var pressureUnit = PressureUnit.localeDefault
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if appState.devices.isEmpty {
            Text("No devices configured").disabled(true)
        }

        ForEach(appState.devices) { device in
            Section(device.name) {
                Text(summaryLine(device)).disabled(true)
                Text(detailLine(device)).disabled(true)
                Text(statusLine(device)).disabled(true)
            }
        }

        Divider()

        Button("Sync Now", action: onSyncNow)

        Menu("Import Aranet CSV…") {
            ForEach(appState.devices) { device in
                Button(device.name) {
                    if let url = pickCSV() {
                        onImportCSV(device.id, url)
                    }
                }
            }
        }

        Button("Open Data Folder") {
            NSWorkspace.shared.open(AppPaths.directory)
        }

        Toggle("Launch at Login", isOn: Binding(
            get: { appState.launchAtLogin },
            set: { onToggleLogin($0) }
        ))

        Button("Settings…") {
            openSettings()
            // Raise the (possibly already-open, buried) Settings window above other apps.
            // Deferred a runloop tick so the window exists on first open.
            DispatchQueue.main.async { SettingsWindowController.shared.bringToFront() }
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Aranet4 Logger") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func summaryLine(_ d: DeviceState) -> String {
        var parts: [String] = []
        if let co2 = d.co2 { parts.append("CO₂ \(co2) ppm") }
        if let t = d.temperature { parts.append(temperatureUnit.format(celsius: t)) }
        if let h = d.humidity { parts.append(String(format: "%.0f%%", h)) }
        if let p = d.pressure { parts.append(pressureUnit.format(hPa: p)) }
        return parts.isEmpty ? "No reading yet" : parts.joined(separator: "   ")
    }

    private func detailLine(_ d: DeviceState) -> String {
        var parts: [String] = []
        if let b = d.battery { parts.append("🔋 \(b)%\(d.batteryIsLow ? " ⚠️ LOW" : "")") }
        if let r = d.rssi { parts.append("📶 \(r) dBm") }
        parts.append("\(d.storedCount) stored")
        return parts.joined(separator: "   ")
    }

    private func statusLine(_ d: DeviceState) -> String {
        var s = d.status.label
        if let sync = d.lastSync {
            s += "  ·  last sync \(relative(sync))"
        }
        return s
    }

    private func pickCSV() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an Aranet Home CSV export for this device"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
