import CoreBluetooth
import Foundation

/// Aranet4 BLE/GATT protocol, ported from the (unofficial) Python `aranet4` library's
/// `client.py`. Only the Aranet4 (CO2/temp/humidity/pressure) device is supported here.
///
/// All multi-byte values on the wire are little-endian.
enum AranetProtocol {

    // MARK: - Identifiers

    /// SAF Tehnika company identifier used in BLE advertisement manufacturer data.
    static let manufacturerID: UInt16 = 0x0702

    /// SAF Tehnika primary service (firmware v1.2.0+).
    static let serviceSAF = CBUUID(string: "FCE0")

    /// Standard Battery service / Battery Level characteristic.
    static let serviceBattery = CBUUID(string: "180F")
    static let charBatteryLevel = CBUUID(string: "2A19")

    /// Generic Access / Device Name.
    static let charDeviceName = CBUUID(string: "2A00")

    // SAF Tehnika characteristics.
    static let charCommand = CBUUID(string: "f0cd1402-95da-4f4b-9ac8-aa55d312af0c")
    static let charCurrentReadings = CBUUID(string: "f0cd1503-95da-4f4b-9ac8-aa55d312af0c")
    static let charCurrentReadingsDetailed = CBUUID(string: "f0cd3001-95da-4f4b-9ac8-aa55d312af0c")
    static let charTotalReadings = CBUUID(string: "f0cd2001-95da-4f4b-9ac8-aa55d312af0c")
    static let charInterval = CBUUID(string: "f0cd2002-95da-4f4b-9ac8-aa55d312af0c")
    static let charSecondsSinceUpdate = CBUUID(string: "f0cd2004-95da-4f4b-9ac8-aa55d312af0c")
    static let charHistoryV2 = CBUUID(string: "f0cd2005-95da-4f4b-9ac8-aa55d312af0c")

    /// History/log parameter codes (from `Param` IntEnum in client.py).
    enum Param: UInt8 {
        case temperature = 1
        case humidity = 2
        case pressure = 3
        case co2 = 4
    }

    // MARK: - Scaling

    /// Apply per-parameter scaling and "invalid reading" magic-number checks. Returns nil for
    /// invalid readings (Aranet4 stores magic values while in CO2 calibration mode).
    /// Mirrors `CurrentReading._set` in client.py.
    static func scaled(_ raw: UInt16, param: Param) -> Double? {
        switch param {
        case .co2:
            if raw >> 15 == 1 { return nil }
            return Double(raw)
        case .pressure:
            if raw >> 15 == 1 { return nil }
            return (Double(raw) * 0.1).rounded(toPlaces: 1)
        case .temperature:
            if (raw >> 14) & 1 == 1 { return nil }
            return (Double(raw) * 0.05).rounded(toPlaces: 2)
        case .humidity:
            if raw >> 8 != 0 { return nil }
            return Double(raw)
        }
    }

    // MARK: - Current readings (GATT characteristic f0cd1503 / f0cd3001)

    struct CurrentReading {
        var co2: Int?
        var temperature: Double?
        var humidity: Double?
        var pressure: Double?
        var battery: Int?
        var interval: Int?
        var ago: Int?
    }

    /// Decode the current-readings characteristic. The basic characteristic is `<HHHBBB`
    /// (co2, temp, pressure, humidity, battery, status); the detailed one (`<HHHBBBHH`) adds
    /// interval and ago. Works for either by length.
    static func decodeCurrent(_ data: Data) -> CurrentReading? {
        guard data.count >= 8 else { return nil }
        let co2Raw = data.u16(0)
        let tempRaw = data.u16(2)
        let presRaw = data.u16(4)
        let humiRaw = UInt16(data[data.startIndex + 6])
        let battery = Int(data[data.startIndex + 7])

        var r = CurrentReading()
        r.co2 = scaled(co2Raw, param: .co2).map { Int($0) }
        r.temperature = scaled(tempRaw, param: .temperature)
        r.pressure = scaled(presRaw, param: .pressure)
        r.humidity = scaled(humiRaw, param: .humidity)
        r.battery = battery

        // Detailed variant: interval (UInt16 @9) and ago (UInt16 @11).
        if data.count >= 13 {
            r.interval = Int(data.u16(9))
            r.ago = Int(data.u16(11))
        }
        return r
    }

    // MARK: - Advertisement parsing (passive, no connection)

    /// Parse current readings + battery from a BLE advertisement's manufacturer data.
    /// Requires the device's "Smart Home integrations" to be enabled (the `integrations`
    /// flag in the manufacturer data); otherwise returns nil. Mirrors `Aranet4Advertisement`.
    static func decodeAdvertisement(name: String?, manufacturerData: Data) -> CurrentReading? {
        // Reconstruct the byte layout the Python code expects: it prepends a leading version
        // byte (0 for Aranet4) so offsets line up with `<xxxxxxxxxHHHBBBHH`.
        var bytes = [UInt8](manufacturerData)
        guard bytes.count >= 5 else { return nil }

        let validName = (name?.hasPrefix("Aranet4")) ?? false
        // For Aranet4 the integrations packet is 7 or 22 bytes (without name) or name starts
        // with "Aranet4"; insert the implicit version byte.
        if validName || bytes.count == 7 || bytes.count == 22 {
            bytes.insert(0, at: 0)
        }

        // Basic info starts at byte 1 after normalization. Bit 5 of the first basic-info byte is
        // the Smart Home integrations flag; require it before trusting measurement fields.
        guard bytes.count > 1 else { return nil }
        let integrations = (bytes[1] & 0x20) != 0
        guard integrations else { return nil }

        // Aranet4 extended layout `<xxxxxxxxxHHHBBBHH`: skip 9 bytes, then
        // co2(H) temp(H) pressure(H) humidity(B) battery(B) status(B) interval(H) ago(H).
        let need = 9 + 2 + 2 + 2 + 1 + 1 + 1 + 2 + 2
        guard bytes.count >= need else { return nil }
        let d = Data(bytes)
        let co2Raw = d.u16(9)
        let tempRaw = d.u16(11)
        let presRaw = d.u16(13)
        let humiRaw = UInt16(bytes[15])
        let battery = Int(bytes[16])
        let interval = Int(d.u16(18))
        let ago = Int(d.u16(20))

        var r = CurrentReading()
        r.co2 = scaled(co2Raw, param: .co2).map { Int($0) }
        r.temperature = scaled(tempRaw, param: .temperature)
        r.pressure = scaled(presRaw, param: .pressure)
        r.humidity = scaled(humiRaw, param: .humidity)
        r.battery = battery
        r.interval = interval
        r.ago = ago
        return r
    }

    // MARK: - History (v2)

    /// Build the command written to the CMD characteristic to start a history read for a
    /// parameter beginning at `startIndex` (1-based). Layout `<BBH` = 0x61, param, start.
    static func historyCommand(param: Param, startIndex: UInt16) -> Data {
        var data = Data()
        data.append(0x61)
        data.append(param.rawValue)
        data.appendLE(max(startIndex, 1))
        return data
    }

    /// Parsed header of a history-v2 packet: `<BHHHHB` then payload values.
    struct HistoryHeader {
        var param: UInt8
        var start: UInt16   // 1-based index of the first value in this packet
        var count: UInt16   // number of values in this packet
    }

    /// Parse one history-v2 packet. Returns the header plus the decoded values (already scaled;
    /// nil for invalid). Returns nil if the packet is malformed.
    static func parseHistoryPacket(_ data: Data, param: Param) -> (HistoryHeader, [Double?])? {
        guard data.count >= 10 else { return nil }
        // 10-byte header `<BHHHHB`, fields (from HistoryHeader in client.py):
        //   param (byte 0), interval (1-2), total_readings (3-4), ago (5-6),
        //   start (7-8), count (byte 9).
        let pkParam = data[data.startIndex + 0]
        let start = data.u16(7)
        let count = UInt16(data[data.startIndex + 9])
        let header = HistoryHeader(param: pkParam, start: start, count: count)

        let payload = data.subdata(in: (data.startIndex + 10)..<data.endIndex)
        let valueSize = (param == .humidity) ? 1 : 2
        guard payload.count >= Int(count) * valueSize else { return nil }
        let usable = payload.count - (payload.count % valueSize)
        var values: [Double?] = []
        values.reserveCapacity(usable / valueSize)
        var i = payload.startIndex
        while i + valueSize <= payload.startIndex + usable {
            let raw: UInt16
            if valueSize == 1 {
                raw = UInt16(payload[i])
            } else {
                raw = UInt16(payload[i]) | (UInt16(payload[i + 1]) << 8)
            }
            values.append(scaled(raw, param: param))
            i += valueSize
        }
        return (header, values)
    }
}

// MARK: - Helpers

extension Data {
    /// Little-endian UInt16 at byte offset `offset` (relative to startIndex).
    func u16(_ offset: Int) -> UInt16 {
        let lo = UInt16(self[startIndex + offset])
        let hi = UInt16(self[startIndex + offset + 1])
        return lo | (hi << 8)
    }

    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    /// Parse a little-endian integer of this Data (used for total readings / interval chars).
    func littleEndianInt() -> Int {
        var result = 0
        for (i, byte) in self.enumerated() {
            result |= Int(byte) << (8 * i)
        }
        return result
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}
