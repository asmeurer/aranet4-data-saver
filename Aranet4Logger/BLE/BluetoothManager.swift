import CoreBluetooth
import Foundation

/// Live advertisement snapshot pushed to the UI (no connection required).
struct LiveReading: Sendable {
    var deviceID: String
    var name: String?
    var rssi: Int
    var reading: AranetProtocol.CurrentReading?
    var date: Date
}

enum BLEError: Error, CustomStringConvertible {
    case poweredOff(CBManagerState)
    case peripheralNotFound
    case connectFailed(String)
    case connectTimeout
    case disconnected(String)
    case gattTimeout(String)
    case missingCharacteristic(String)

    var description: String {
        switch self {
        case .poweredOff(let s): return "Bluetooth not powered on (state \(s.rawValue))"
        case .peripheralNotFound: return "Peripheral not found"
        case .connectFailed(let m): return "Connect failed: \(m)"
        case .connectTimeout: return "Connection timed out"
        case .disconnected(let m): return "Disconnected: \(m)"
        case .gattTimeout(let m): return "GATT operation timed out: \(m)"
        case .missingCharacteristic(let m): return "Missing characteristic: \(m)"
        }
    }
}

/// Owns the single `CBCentralManager`. Runs a continuous passive scan to feed live menu
/// values, and performs serialized connect + history-download sessions on demand.
///
/// All CoreBluetooth state is mutated only on `queue`. Marked @unchecked Sendable because
/// the class guards its own state on that serial queue (Swift 5 language mode).
final class BluetoothManager: NSObject, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.asmeurer.Aranet4Logger.ble")
    private var central: CBCentralManager!
    private let sessionLock = AsyncLock()

    // State guarded by `queue`.
    private var state: CBManagerState = .unknown
    private var poweredOnWaiters: [Int: CheckedContinuation<Void, Error>] = [:]
    private var poweredOnWaiterCounter = 0
    private var discovered: [UUID: CBPeripheral] = [:]
    private var connectWaiters: [UUID: CheckedContinuation<CBPeripheral, Error>] = [:]
    private var activeSessions: [UUID: AranetSession] = [:]

    /// Called on the BLE queue for each Aranet advertisement seen.
    var onLiveReading: (@Sendable (LiveReading) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: - Public API

    /// Connect to a device, download history since `since`, and return the new readings plus
    /// the latest current reading. Serialized so only one device is contacted at a time.
    func sync(deviceID: UUID, since: Date?, connectTimeout: TimeInterval) async throws -> SyncResult {
        await sessionLock.acquire()
        defer { Task { await sessionLock.release() } }

        try await waitUntilPoweredOn()
        let peripheral = try retrievePeripheral(deviceID)
        let session = AranetSession(peripheral: peripheral, queue: queue)
        setSession(session, for: deviceID)
        defer {
            clearSession(for: deviceID)
            disconnect(peripheral)
        }

        try await connect(peripheral, timeout: connectTimeout)
        return try await session.run(since: since)
    }

    // MARK: - Powered-on gate

    /// Wait until the manager reports `.poweredOn`. macOS suspends the Bluetooth session while
    /// the app is idle between polls (reporting `.poweredOff` transiently), so we wait through
    /// that rather than failing immediately — bounded by `timeout` so genuinely-off Bluetooth
    /// still fails the attempt. Only the permanent states fail fast.
    private func waitUntilPoweredOn(timeout: TimeInterval = 60) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                switch self.state {
                case .poweredOn:
                    cont.resume()
                case .unsupported, .unauthorized:
                    cont.resume(throwing: BLEError.poweredOff(self.state))
                default:
                    // .unknown, .resetting, .poweredOff — wait for a transition to poweredOn.
                    let id = self.poweredOnWaiterCounter
                    self.poweredOnWaiterCounter += 1
                    self.poweredOnWaiters[id] = cont
                    self.queue.asyncAfter(deadline: .now() + timeout) {
                        if let waiter = self.poweredOnWaiters.removeValue(forKey: id) {
                            waiter.resume(throwing: BLEError.poweredOff(self.state))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Connect / disconnect

    private func retrievePeripheral(_ id: UUID) throws -> CBPeripheral {
        if let p = discovered[id] { return p }
        if let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            discovered[id] = p
            return p
        }
        throw BLEError.peripheralNotFound
    }

    private func connect(_ peripheral: CBPeripheral, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CBPeripheral, Error>) in
            queue.async {
                let id = peripheral.identifier
                self.connectWaiters[id] = cont
                self.central.connect(peripheral, options: nil)
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    if let waiter = self.connectWaiters.removeValue(forKey: id) {
                        self.central.cancelPeripheralConnection(peripheral)
                        waiter.resume(throwing: BLEError.connectTimeout)
                    }
                }
            }
        }
    }

    private func disconnect(_ peripheral: CBPeripheral) {
        queue.async {
            if peripheral.state == .connected || peripheral.state == .connecting {
                self.central.cancelPeripheralConnection(peripheral)
            }
        }
    }

    private func setSession(_ session: AranetSession, for id: UUID) {
        queue.sync { activeSessions[id] = session }
    }

    private func clearSession(for id: UUID) {
        queue.sync { activeSessions[id] = nil }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if central.state == .poweredOn {
            for w in poweredOnWaiters.values { w.resume() }
            poweredOnWaiters.removeAll()
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        } else if central.state == .unsupported || central.state == .unauthorized {
            // Permanent failure: fail any waiters now. Transient .poweredOff/.resetting waiters
            // keep waiting (their own timeout bounds them).
            for w in poweredOnWaiters.values { w.resume(throwing: BLEError.poweredOff(central.state)) }
            poweredOnWaiters.removeAll()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data

        // Only care about Aranet devices: either a recognizable name or SAF manufacturer ID.
        var isAranet = (name?.contains("Aranet")) ?? false
        if let mfg = mfgData, mfg.count >= 2 {
            let companyID = UInt16(mfg[mfg.startIndex]) | (UInt16(mfg[mfg.startIndex + 1]) << 8)
            if companyID == AranetProtocol.manufacturerID { isAranet = true }
        }
        guard isAranet else { return }

        discovered[peripheral.identifier] = peripheral

        var reading: AranetProtocol.CurrentReading?
        if let mfg = mfgData, mfg.count >= 2 {
            // Strip the 2-byte company ID prefix before decoding, matching the Python lib which
            // receives manufacturer payload keyed by company ID.
            let payload = mfg.subdata(in: (mfg.startIndex + 2)..<mfg.endIndex)
            reading = AranetProtocol.decodeAdvertisement(name: name, manufacturerData: payload)
        }

        let live = LiveReading(
            deviceID: peripheral.identifier.uuidString,
            name: name,
            rssi: RSSI.intValue,
            reading: reading,
            date: Date()
        )
        onLiveReading?(live)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let waiter = connectWaiters.removeValue(forKey: peripheral.identifier) {
            waiter.resume(returning: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        if let waiter = connectWaiters.removeValue(forKey: peripheral.identifier) {
            waiter.resume(throwing: BLEError.connectFailed(error?.localizedDescription ?? "unknown"))
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        // If a connection attempt was still pending, fail it.
        if let waiter = connectWaiters.removeValue(forKey: peripheral.identifier) {
            waiter.resume(throwing: BLEError.disconnected(error?.localizedDescription ?? "unknown"))
        }
        // Notify an active session so any in-flight GATT await fails fast.
        activeSessions[peripheral.identifier]?.handleDisconnect(
            error: error?.localizedDescription ?? "peripheral disconnected"
        )
    }
}
