import AppKit
import Foundation
import Observation

/// Loads the last 24 hours of history for the menu's inline sparklines. The data is kept
/// warm in the background — reloaded whenever a device stores new readings — because a
/// native menu draws its items the moment it opens and can't wait for an async query.
@MainActor
@Observable
final class MenuChartsModel {
    /// The menu always shows the last 24 hours at the sensors' native 5-minute grid.
    static let span: TimeInterval = 86_400
    static let bucketSeconds = 300

    private let appState: AppState
    private let database: Database?

    private(set) var series: [ChartsModel.DeviceSeries] = []

    /// Invalidates stale loads: only the newest reload may publish results.
    private var loadGeneration = 0
    private var refreshTimer: Timer?

    init(appState: AppState, database: Database?) {
        self.appState = appState
        self.database = database
        reload()
        observeStoredCounts()
        startRefreshTimer()
    }

    var visibleSeries: [ChartsModel.DeviceSeries] {
        windowedSeries(endingAt: Date())
    }

    var hasData: Bool { visibleSeries.contains { !$0.points.isEmpty } }

    /// A line may bridge one missing bucket (a single dropped sample); longer gaps break it.
    var maxGap: TimeInterval { TimeInterval(2 * Self.bucketSeconds) }

    func reload() {
        guard let database else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let devices = appState.devices.enumerated().map { (slot: $0, id: $1.id, name: $1.name) }

        Task {
            do {
                let from = Date().addingTimeInterval(-Self.span)
                var loaded: [ChartsModel.DeviceSeries] = []
                for device in devices {
                    let points = try await database.history(
                        device: device.id, from: from, bucketSeconds: Self.bucketSeconds
                    )
                    loaded.append(ChartsModel.DeviceSeries(
                        id: device.id, name: device.name, slot: device.slot, points: points
                    ))
                }
                guard generation == loadGeneration else { return }
                series = loaded
                #if DEBUG
                dumpImageIfRequested()
                #endif
            } catch {
                AppLog.shared.error("Menu chart history query failed: \(error)")
            }
        }
    }

    /// Reload whenever any device's stored count changes (i.e. a sync landed new readings),
    /// re-registering because observation tracking is one-shot.
    private func observeStoredCounts() {
        withObservationTracking {
            _ = appState.devices.map { ($0.id, $0.storedCount) }
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.reload()
                self.observeStoredCounts()
            }
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(Self.bucketSeconds),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    private func windowedSeries(endingAt end: Date) -> [ChartsModel.DeviceSeries] {
        let start = end.addingTimeInterval(-Self.span)
        return series.map { device in
            ChartsModel.DeviceSeries(
                id: device.id,
                name: device.name,
                slot: device.slot,
                points: device.points.filter { $0.timestamp >= start && $0.timestamp <= end }
            )
        }
    }

    #if DEBUG
    /// Test hook for scripted UI screenshots: write the rendered sparkline image as a PNG to
    /// the path in ARANET4_DUMP_MENU_CHARTS once data is loaded, over the menu-like surface
    /// color so dynamic colors can be judged in context.
    private func dumpImageIfRequested() {
        guard hasData,
              let path = ProcessInfo.processInfo.environment["ARANET4_DUMP_MENU_CHARTS"]
        else { return }
        let defaults = UserDefaults.standard
        let images = ChartMetric.allCases.compactMap { metric in
            MenuSparkline.rowImage(
                metric: metric,
                series: series,
                temperatureUnit: defaults.string(forKey: SettingsKeys.temperatureUnit)
                    .flatMap(TemperatureUnit.init) ?? .localeDefault,
                pressureUnit: defaults.string(forKey: SettingsKeys.pressureUnit)
                    .flatMap(PressureUnit.init) ?? .localeDefault,
                co2Threshold: defaults.object(forKey: SettingsKeys.co2Threshold) == nil
                    ? SettingsKeys.defaultCO2Threshold
                    : defaults.integer(forKey: SettingsKeys.co2Threshold),
                span: Self.span,
                maxGap: maxGap
            )
        }
        guard !images.isEmpty else { return }
        let spacing: CGFloat = 6
        let size = NSSize(
            width: MenuSparkline.width,
            height: CGFloat(images.count) * MenuSparkline.height
                + CGFloat(images.count - 1) * spacing
        )
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = size
        // The dump draws outside any view, so resolve dynamic colors under the requested
        // appearance explicitly (in the real menu, AppKit sets this per draw).
        let dark = ProcessInfo.processInfo.environment["ARANET4_APPEARANCE"] == "dark"
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
            for (index, image) in images.enumerated() {
                image.draw(in: NSRect(
                    x: 0,
                    y: size.height - CGFloat(index + 1) * MenuSparkline.height
                        - CGFloat(index) * spacing,
                    width: MenuSparkline.width,
                    height: MenuSparkline.height
                ))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        do {
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            AppLog.shared.error("Menu chart dump failed: \(error)")
        }
    }
    #endif
}
