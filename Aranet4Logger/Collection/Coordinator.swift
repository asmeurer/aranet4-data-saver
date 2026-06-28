import Foundation

/// Owns the Bluetooth manager, database, and per-device collection loops, and pushes updates
/// into the observable `AppState`. One instance lives for the app's lifetime.
@MainActor
final class Coordinator {
    let appState: AppState
    private let bluetooth = BluetoothManager()
    private var database: Database?
    private var config = AppConfig.default
    private var collectorTasks: [String: Task<Void, Never>] = [:]
    private struct SyncSignal {
        var id: UUID
        var resume: () -> Void
    }
    /// Manual "Sync now" triggers, one continuation stream per device.
    private var syncSignals: [String: SyncSignal] = [:]
    /// Keeps the process out of App Nap (which throttles timers and the CoreBluetooth state
    /// callback for a windowless menu bar app). Idle system sleep is still allowed — history
    /// backfill covers any sleep gap.
    private var activityToken: NSObjectProtocol?

    init() {
        self.appState = AppState()
    }

    func start() {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Continuously logging Aranet4 sensor data"
        )
        config = ConfigStore.load()
        do {
            database = try Database()
        } catch {
            AppLog.shared.error("Failed to open database: \(error)")
        }

        appState.devices = config.devices.map { DeviceState(id: $0.id, name: $0.name) }

        // Funnel live advertisements into AppState on the main actor.
        bluetooth.onLiveReading = { [weak self] live in
            Task { @MainActor in self?.applyLive(live) }
        }

        AppLog.shared.info("Aranet4Logger started with \(config.devices.count) device(s)")

        for device in config.devices {
            startCollector(for: device)
        }
        refreshStoredCounts()
    }

    /// Trigger an immediate sync for all devices.
    func syncNow() {
        for signal in Array(syncSignals.values) { signal.resume() }
    }

    /// Import an official Aranet Home CSV export for a device.
    func importCSV(url: URL, deviceID: String) {
        guard let database else { return }
        Task {
            do {
                let result = try await CSVImporter.import(url: url, deviceID: deviceID, database: database)
                let count = try await database.count(device: deviceID)
                AppLog.shared.info("Imported \(url.lastPathComponent) for \(deviceID): parsed \(result.parsed), +\(result.inserted) new (total \(count))")
                await MainActor.run { appState.device(deviceID)?.storedCount = count }
            } catch {
                AppLog.shared.error("CSV import failed for \(deviceID): \(error)")
            }
        }
    }

    // MARK: - Device discovery

    /// Add a newly seen sensor to the persisted config and start logging it. Called the first
    /// time a device appears in the scan. Idempotent: a device already in the config is left
    /// untouched, so a user-chosen name is never overwritten by a later re-discovery.
    private func addDiscoveredDevice(id: String, name: String?) {
        guard !config.devices.contains(where: { $0.id == id }) else { return }
        let friendly = name ?? "Aranet4 \(id.prefix(8))"
        let device = DeviceConfig(id: id, name: friendly)
        config.devices.append(device)
        ConfigStore.save(config)
        appState.devices.append(DeviceState(id: id, name: friendly))
        AppLog.shared.info("Discovered new device \(id) (\(friendly)); added to config")
        startCollector(for: device)
        Task {
            if let count = try? await database?.count(device: id) {
                await MainActor.run { appState.device(id)?.storedCount = count }
            }
        }
    }

    /// Rename a configured device. Persists immediately and updates the live UI. Called from the
    /// Settings window as the user edits the name field.
    func rename(deviceID: String, to newName: String) {
        guard let idx = config.devices.firstIndex(where: { $0.id == deviceID }) else { return }
        config.devices[idx].name = newName
        ConfigStore.save(config)
        appState.device(deviceID)?.name = newName
    }

    // MARK: - Live data

    private func applyLive(_ live: LiveReading) {
        appState.bluetoothReady = true
        if appState.device(live.deviceID) == nil {
            addDiscoveredDevice(id: live.deviceID, name: live.name)
        }
        guard let dev = appState.device(live.deviceID) else { return }
        dev.rssi = live.rssi
        dev.lastSeen = live.date
        if let r = live.reading {
            if let v = r.co2 { dev.co2 = v }
            if let v = r.temperature { dev.temperature = v }
            if let v = r.humidity { dev.humidity = v }
            if let v = r.pressure { dev.pressure = v }
            if let v = r.battery { dev.battery = v }
        }
    }

    // MARK: - Collectors

    private func startCollector(for device: DeviceConfig) {
        let uuid = UUID(uuidString: device.id)
        let task = Task { [weak self] in
            guard let self else { return }
            guard let uuid else {
                await MainActor.run {
                    self.appState.device(device.id)?.status = .failed("Invalid device id")
                }
                AppLog.shared.error("Invalid device id \(device.id)")
                return
            }
            while !Task.isCancelled {
                await self.syncOnce(deviceID: device.id, uuid: uuid)
                await self.waitForNextCycle(deviceID: device.id)
            }
        }
        collectorTasks[device.id] = task
    }

    /// One sync attempt cycle, with retries/backoff. Errors are logged in full and surfaced in
    /// the UI; the loop always continues (downtime is harmless thanks to on-device backfill).
    private func syncOnce(deviceID: String, uuid: UUID) async {
        guard let database else { return }
        await MainActor.run { appState.device(deviceID)?.status = .syncing }

        let retries = max(1, config.connectRetries)
        for attempt in 1...retries {
            if attempt > 1 {
                await MainActor.run { appState.device(deviceID)?.status = .retrying(attempt: attempt) }
            }
            do {
                let since = try await database.lastTimestamp(device: deviceID)
                let result = try await bluetooth.sync(
                    deviceID: uuid,
                    since: since,
                    connectTimeout: config.connectTimeout
                )
                let inserted = try await database.insert(result.readings)
                let count = try await database.count(device: deviceID)
                await MainActor.run {
                    let dev = appState.device(deviceID)
                    dev?.status = .ok
                    dev?.lastSync = Date()
                    dev?.storedCount = count
                    if let b = result.battery { dev?.battery = b }
                    if let c = result.current {
                        if let v = c.co2 { dev?.co2 = v }
                        if let v = c.temperature { dev?.temperature = v }
                        if let v = c.humidity { dev?.humidity = v }
                        if let v = c.pressure { dev?.pressure = v }
                    }
                }
                AppLog.shared.info("Synced \(deviceID): +\(inserted) new (total \(count), device log \(result.total))")
                return
            } catch {
                let message = "\(error)"
                AppLog.shared.error("Sync attempt \(attempt)/\(retries) for \(deviceID) failed: \(message)")
                if attempt < retries {
                    let backoff = config.retryBackoff * Double(attempt)
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                } else {
                    await MainActor.run {
                        appState.device(deviceID)?.status = .failed(shortError(message))
                    }
                }
            }
        }
    }

    /// Wait until the next poll interval elapses or a manual "Sync now" arrives.
    private func waitForNextCycle(deviceID: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let waitID = UUID()
            var resumed = false
            var sleepTask: Task<Void, Never>?
            let resumeOnce = {
                guard !resumed else { return }
                resumed = true
                sleepTask?.cancel()
                if self.syncSignals[deviceID]?.id == waitID {
                    self.syncSignals[deviceID] = nil
                }
                cont.resume()
            }
            syncSignals[deviceID] = SyncSignal(id: waitID, resume: resumeOnce)
            sleepTask = Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64(config.pollInterval * 1_000_000_000))
                } catch {
                    return
                }
                await MainActor.run {
                    resumeOnce()
                }
            }
        }
    }

    private func refreshStoredCounts() {
        guard let database else { return }
        for device in config.devices {
            Task {
                if let count = try? await database.count(device: device.id) {
                    await MainActor.run { appState.device(device.id)?.storedCount = count }
                }
            }
        }
    }

    private func shortError(_ message: String) -> String {
        if message.count <= 60 { return message }
        return String(message.prefix(57)) + "…"
    }
}
