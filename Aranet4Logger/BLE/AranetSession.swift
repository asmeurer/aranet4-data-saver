import CoreBluetooth
import Foundation

/// Result of a single sync: new history readings plus the latest live snapshot.
struct SyncResult: Sendable {
    var readings: [Reading]
    var current: AranetProtocol.CurrentReading?
    var total: Int
    var battery: Int?
}

/// Drives the GATT workflow for one connected Aranet4 peripheral: discover services, read
/// metadata, and download history. Acts as the peripheral's delegate. All state is touched on
/// the shared BLE queue, so CoreBluetooth callbacks and our awaits stay serialized.
final class AranetSession: NSObject, @unchecked Sendable {
    private let peripheral: CBPeripheral
    private let queue: DispatchQueue
    private let gattTimeout: TimeInterval = 30

    private var discoverServicesCont: CheckedContinuation<Void, Error>?
    private var discoverCharsCont: CheckedContinuation<Void, Error>?
    private var readConts: [CBUUID: CheckedContinuation<Data, Error>] = [:]
    private var writeConts: [CBUUID: CheckedContinuation<Void, Error>] = [:]

    init(peripheral: CBPeripheral, queue: DispatchQueue) {
        self.peripheral = peripheral
        self.queue = queue
        super.init()
        peripheral.delegate = self
    }

    /// Called by BluetoothManager on disconnect to fail any in-flight operation.
    func handleDisconnect(error: String) {
        queue.async {
            let err = BLEError.disconnected(error)
            self.discoverServicesCont?.resume(throwing: err); self.discoverServicesCont = nil
            self.discoverCharsCont?.resume(throwing: err); self.discoverCharsCont = nil
            for (_, c) in self.readConts { c.resume(throwing: err) }
            self.readConts.removeAll()
            for (_, c) in self.writeConts { c.resume(throwing: err) }
            self.writeConts.removeAll()
        }
    }

    // MARK: - Workflow

    func run(since: Date?) async throws -> SyncResult {
        try await discoverServices([
            AranetProtocol.serviceSAF,
            AranetProtocol.serviceBattery,
        ])
        guard let safService = service(AranetProtocol.serviceSAF) else {
            throw BLEError.missingCharacteristic("SAF service \(AranetProtocol.serviceSAF)")
        }
        try await discoverCharacteristics(nil, for: safService)
        if let batteryService = service(AranetProtocol.serviceBattery) {
            try await discoverCharacteristics([AranetProtocol.charBatteryLevel], for: batteryService)
        }

        let cmdChar = try characteristic(AranetProtocol.charCommand)
        let historyChar = try characteristic(AranetProtocol.charHistoryV2)
        let totalChar = try characteristic(AranetProtocol.charTotalReadings)
        let intervalChar = try characteristic(AranetProtocol.charInterval)
        let agoChar = try characteristic(AranetProtocol.charSecondsSinceUpdate)

        let total = try await read(totalChar).littleEndianInt()
        let interval = try await read(intervalChar).littleEndianInt()
        let secondsSinceUpdate = try await read(agoChar).littleEndianInt()

        // Best-effort current reading + battery.
        var current: AranetProtocol.CurrentReading?
        if let currentChar = optionalCharacteristic(AranetProtocol.charCurrentReadingsDetailed)
            ?? optionalCharacteristic(AranetProtocol.charCurrentReadings) {
            current = AranetProtocol.decodeCurrent(try await read(currentChar))
        }
        var battery = current?.battery
        if let batteryChar = optionalCharacteristic(AranetProtocol.charBatteryLevel),
           let data = try? await read(batteryChar), let first = data.first {
            battery = Int(first)
        }

        let now = Date()
        let lastLogged = now.addingTimeInterval(-Double(secondsSinceUpdate))

        guard total > 0, interval > 0 else {
            return SyncResult(readings: [], current: current, total: total, battery: battery)
        }

        // Decide where to resume. Keep a small overlap; dedup absorbs it.
        let startIndex: Int
        if let since {
            let missing = Int(((lastLogged.timeIntervalSince(since)) / Double(interval)).rounded(.down))
            startIndex = max(1, total - max(0, missing) - 2)
        } else {
            startIndex = 1
        }

        if startIndex > total {
            return SyncResult(readings: [], current: current, total: total, battery: battery)
        }

        let co2 = try await downloadParam(.co2, total: total, startIndex: startIndex,
                                          cmd: cmdChar, history: historyChar)
        let temp = try await downloadParam(.temperature, total: total, startIndex: startIndex,
                                           cmd: cmdChar, history: historyChar)
        let humi = try await downloadParam(.humidity, total: total, startIndex: startIndex,
                                           cmd: cmdChar, history: historyChar)
        let pres = try await downloadParam(.pressure, total: total, startIndex: startIndex,
                                           cmd: cmdChar, history: historyChar)

        let deviceID = peripheral.identifier.uuidString
        var readings: [Reading] = []
        readings.reserveCapacity(total - startIndex + 1)
        for j in (startIndex - 1)..<total {
            let age = Double(total - j - 1) * Double(interval)
            // Snap to the logging-interval grid so the same reading gets a stable key across
            // syncs (enables dedup) and aligns with imported CSV data.
            let ts = TimeGrid.snap(lastLogged.addingTimeInterval(-age), intervalSeconds: interval)
            readings.append(Reading(
                deviceID: deviceID,
                timestamp: ts,
                co2: co2[j].map { Int($0) },
                temperature: temp[j],
                humidity: humi[j],
                pressure: pres[j]
            ))
        }

        return SyncResult(readings: readings, current: current, total: total, battery: battery)
    }

    /// Download one parameter's history into an array indexed 0..<total. Mirrors
    /// `_get_records_v2`.
    private func downloadParam(_ param: AranetProtocol.Param, total: Int, startIndex: Int,
                               cmd: CBCharacteristic, history: CBCharacteristic) async throws -> [Double?] {
        var result = [Double?](repeating: nil, count: total)
        var received = [Bool](repeating: false, count: total)
        var receivedCount = 0
        let expectedCount = total - startIndex + 1
        try await write(AranetProtocol.historyCommand(param: param, startIndex: UInt16(startIndex)),
                        char: cmd)

        var safety = 0
        let maxIterations = total + 64
        while receivedCount < expectedCount && safety < maxIterations {
            safety += 1
            let packet = try await read(history)
            guard let (header, values) = AranetProtocol.parseHistoryPacket(packet, param: param) else {
                throw BLEError.malformedHistoryPacket("\(param) at index \(startIndex)")
            }
            if header.param != param.rawValue || header.count == 0 { continue }

            var idx = Int(header.start) - 1
            let blockEnd = Int(header.start) - 1 + Int(header.count)
            for v in values {
                if idx >= total || idx >= blockEnd { break }
                if idx >= startIndex - 1 {
                    result[idx] = v
                    if !received[idx] {
                        received[idx] = true
                        receivedCount += 1
                    }
                }
                idx += 1
            }
        }
        guard receivedCount == expectedCount else {
            throw BLEError.incompleteHistoryDownload(
                "\(param) received \(receivedCount)/\(expectedCount) values from index \(startIndex)"
            )
        }
        return result
    }

    // MARK: - Lookup helpers

    private func service(_ uuid: CBUUID) -> CBService? {
        peripheral.services?.first { $0.uuid == uuid }
    }

    private func optionalCharacteristic(_ uuid: CBUUID) -> CBCharacteristic? {
        for s in peripheral.services ?? [] {
            if let c = s.characteristics?.first(where: { $0.uuid == uuid }) { return c }
        }
        return nil
    }

    private func characteristic(_ uuid: CBUUID) throws -> CBCharacteristic {
        guard let c = optionalCharacteristic(uuid) else {
            throw BLEError.missingCharacteristic(uuid.uuidString)
        }
        return c
    }

    // MARK: - Async GATT primitives

    private func discoverServices(_ uuids: [CBUUID]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                self.discoverServicesCont = cont
                self.peripheral.discoverServices(uuids)
                self.timeout(after: self.gattTimeout, label: "discoverServices") {
                    if let c = self.discoverServicesCont { self.discoverServicesCont = nil
                        c.resume(throwing: BLEError.gattTimeout("discoverServices")) }
                }
            }
        }
    }

    private func discoverCharacteristics(_ uuids: [CBUUID]?, for service: CBService) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                self.discoverCharsCont = cont
                self.peripheral.discoverCharacteristics(uuids, for: service)
                self.timeout(after: self.gattTimeout, label: "discoverCharacteristics") {
                    if let c = self.discoverCharsCont { self.discoverCharsCont = nil
                        c.resume(throwing: BLEError.gattTimeout("discoverCharacteristics")) }
                }
            }
        }
    }

    private func read(_ char: CBCharacteristic) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            queue.async {
                self.readConts[char.uuid] = cont
                self.peripheral.readValue(for: char)
                self.timeout(after: self.gattTimeout, label: "read \(char.uuid)") {
                    if let c = self.readConts.removeValue(forKey: char.uuid) {
                        c.resume(throwing: BLEError.gattTimeout("read \(char.uuid)"))
                    }
                }
            }
        }
    }

    private func write(_ data: Data, char: CBCharacteristic) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                self.writeConts[char.uuid] = cont
                self.peripheral.writeValue(data, for: char, type: .withResponse)
                self.timeout(after: self.gattTimeout, label: "write \(char.uuid)") {
                    if let c = self.writeConts.removeValue(forKey: char.uuid) {
                        c.resume(throwing: BLEError.gattTimeout("write \(char.uuid)"))
                    }
                }
            }
        }
    }

    private func timeout(after seconds: TimeInterval, label: String, _ work: @escaping () -> Void) {
        queue.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

// MARK: - CBPeripheralDelegate

extension AranetSession: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let cont = discoverServicesCont else { return }
        discoverServicesCont = nil
        if let error { cont.resume(throwing: error) } else { cont.resume() }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let cont = discoverCharsCont else { return }
        discoverCharsCont = nil
        if let error { cont.resume(throwing: error) } else { cont.resume() }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let cont = readConts.removeValue(forKey: characteristic.uuid) else { return }
        if let error {
            cont.resume(throwing: error)
        } else {
            cont.resume(returning: characteristic.value ?? Data())
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let cont = writeConts.removeValue(forKey: characteristic.uuid) else { return }
        if let error { cont.resume(throwing: error) } else { cont.resume() }
    }
}
