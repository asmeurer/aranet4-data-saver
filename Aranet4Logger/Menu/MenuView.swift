import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The menu bar title: either the plain status icon, or a selected sensor reading as text
/// (prefixed with a warning glyph when a device has failed, is stale, has a low battery, or —
/// if enabled — reads CO₂ above the configured threshold).
struct MenuBarLabel: View {
    var appState: AppState

    @AppStorage(SettingsKeys.menuBarMetric) private var menuBarMetric = MenuBarMetric.co2
    @AppStorage(SettingsKeys.menuBarDeviceID) private var menuBarDeviceID = ""
    @AppStorage(SettingsKeys.temperatureUnit) private var temperatureUnit = TemperatureUnit.localeDefault
    @AppStorage(SettingsKeys.pressureUnit) private var pressureUnit = PressureUnit.localeDefault
    @AppStorage(SettingsKeys.co2Threshold) private var co2Threshold = SettingsKeys.defaultCO2Threshold
    @AppStorage(SettingsKeys.co2MenuBarWarning) private var co2MenuBarWarning = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if menuBarMetric == .none {
                Image(systemName: appState.statusSymbol(co2Alert: co2Alert))
            } else if let reading = readingParts {
                // Drawn into a template image because MenuBarExtra ignores font modifiers on
                // its label text — this is the only way to get a genuinely smaller unit tag.
                Image(nsImage: Self.readingImage(
                    value: reading.value, unit: reading.unit, warning: warningActive
                ))
            } else {
                // Metric selected but no value yet — fall back to the status icon.
                Image(systemName: appState.statusSymbol(co2Alert: co2Alert))
            }
        }
        .onAppear {
            #if DEBUG
            // Test hooks for scripted UI screenshots: open the Charts window at launch,
            // optionally forcing an appearance.
            if ProcessInfo.processInfo.environment["ARANET4_APPEARANCE"] == "dark" {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
            if ProcessInfo.processInfo.environment["ARANET4_SHOW_CHARTS"] == "1" {
                openWindow(id: ChartsView.windowID)
                DispatchQueue.main.async { WindowFronter.charts.bringToFront() }
            }
            if ProcessInfo.processInfo.environment["ARANET4_SHOW_ABOUT"] == "1" {
                openWindow(id: AboutView.windowID)
                DispatchQueue.main.async { WindowFronter.about.bringToFront() }
            }
            #endif
        }
    }

    /// The chosen device, falling back to the first configured device.
    private var device: DeviceState? {
        appState.device(menuBarDeviceID) ?? appState.devices.first
    }

    /// True when any device's live CO₂ is at or above the warning threshold.
    private var co2Alert: Bool {
        let threshold = SettingsKeys.clampedCO2Threshold(co2Threshold)
        return co2MenuBarWarning && appState.devices.contains { ($0.co2 ?? 0) >= threshold }
    }

    private var warningActive: Bool {
        appState.hasFailure || appState.hasWarning || co2Alert
    }

    /// Render the reading with the unit stacked in small type under the number, so the unit
    /// costs no extra menu bar width. Drawn into a template image (MenuBarExtra ignores font
    /// modifiers on label text, and only an image can hold a two-line layout); the menu bar
    /// tints it for light/dark, so the warning glyph uses the monochrome text presentation
    /// of U+26A0.
    private static func readingImage(value: String, unit: String, warning: Bool) -> NSImage {
        let valueFont = NSFont.menuBarFont(ofSize: 13)
        let unitFont = NSFont.menuBarFont(ofSize: 7)
        let valueText = NSMutableAttributedString()
        if warning {
            valueText.append(NSAttributedString(string: "⚠\u{FE0E} ", attributes: [.font: valueFont]))
        }
        valueText.append(NSAttributedString(string: value, attributes: [.font: valueFont]))
        valueText.addAttribute(
            .foregroundColor, value: NSColor.black,
            range: NSRange(location: 0, length: valueText.length)
        )
        let unitText = NSAttributedString(
            string: unit,
            attributes: [.font: unitFont, .foregroundColor: NSColor.black]
        )
        let valueSize = valueText.size()
        let unitSize = unitText.size()
        let width = ceil(max(valueSize.width, unitSize.width))
        // Tuck the two lines together; the fonts' built-in leading is generous.
        let overlap: CGFloat = 4
        let height = ceil(valueSize.height + unitSize.height - overlap)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            unitText.draw(at: NSPoint(x: (width - unitSize.width) / 2, y: 0))
            valueText.draw(at: NSPoint(x: (width - valueSize.width) / 2, y: unitSize.height - overlap))
            return true
        }
        image.isTemplate = true
        return image
    }

    private var readingParts: (value: String, unit: String)? {
        guard let device else { return nil }
        return menuBarMetric.menuBarParts(
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
    var updater: UpdaterManager
    var onSyncNow: () -> Void
    var onToggleLogin: (Bool) -> Void
    /// Import action for an Aranet CSV export targeting a specific device.
    var onImportCSV: (_ deviceID: String, _ url: URL) -> Void

    @AppStorage(SettingsKeys.temperatureUnit) private var temperatureUnit = TemperatureUnit.localeDefault
    @AppStorage(SettingsKeys.pressureUnit) private var pressureUnit = PressureUnit.localeDefault
    @AppStorage(SettingsKeys.co2Threshold) private var co2Threshold = SettingsKeys.defaultCO2Threshold
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

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

        Button("Charts…") {
            openWindow(id: ChartsView.windowID)
            // Raise the (possibly already-open, buried) window above other apps.
            // Deferred a runloop tick so the window exists on first open.
            DispatchQueue.main.async { WindowFronter.charts.bringToFront() }
        }

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

        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)

        Button("Settings…") {
            openSettings()
            // Raise the (possibly already-open, buried) Settings window above other apps.
            // Deferred a runloop tick so the window exists on first open.
            DispatchQueue.main.async { WindowFronter.settings.bringToFront() }
        }
        .keyboardShortcut(",")

        Divider()

        Text("Version \(AboutView.version)").disabled(true)

        Button("About Aranet4 Logger") {
            openWindow(id: AboutView.windowID)
            // Raise the (possibly already-open, buried) window above other apps.
            // Deferred a runloop tick so the window exists on first open.
            DispatchQueue.main.async { WindowFronter.about.bringToFront() }
        }

        Button("Quit Aranet4 Logger") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func summaryLine(_ d: DeviceState) -> String {
        var parts: [String] = []
        let threshold = SettingsKeys.clampedCO2Threshold(co2Threshold)
        if let co2 = d.co2 { parts.append("CO₂ \(co2) ppm\(co2 >= threshold ? " ⚠️ HIGH" : "")") }
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
