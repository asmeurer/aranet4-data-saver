import Foundation
import XCTest

final class AranetProtocolTests: XCTestCase {
    func testMismatchedHistoryPacketReturnsHeaderBeforePayloadValidation() {
        var packet = Data()
        packet.append(AranetProtocol.Param.humidity.rawValue)
        packet.appendLE(0) // interval
        packet.appendLE(0) // total_readings
        packet.appendLE(0) // ago
        packet.appendLE(7) // start
        packet.append(2) // count
        packet.append(contentsOf: [40, 41])

        let parsed = AranetProtocol.parseHistoryPacket(packet, param: .co2)

        XCTAssertEqual(parsed?.0.param, AranetProtocol.Param.humidity.rawValue)
        XCTAssertEqual(parsed?.0.start, 7)
        XCTAssertEqual(parsed?.0.count, 2)
        XCTAssertEqual(parsed?.1.count, 0)
    }

    // MARK: - Scaling

    func testScaling() {
        XCTAssertEqual(AranetProtocol.scaled(637, param: .co2), 637)
        XCTAssertEqual(AranetProtocol.scaled(491, param: .temperature)!, 24.55, accuracy: 0.001)
        XCTAssertEqual(AranetProtocol.scaled(8384, param: .pressure)!, 838.4, accuracy: 0.001)
        XCTAssertEqual(AranetProtocol.scaled(33, param: .humidity), 33)
    }

    func testScalingInvalidFlags() {
        // CO2 / pressure invalid when bit 15 set.
        XCTAssertNil(AranetProtocol.scaled(0x8000 | 600, param: .co2))
        XCTAssertNil(AranetProtocol.scaled(0x8000 | 8384, param: .pressure))
        // Temperature invalid when bit 14 set.
        XCTAssertNil(AranetProtocol.scaled(0x4000 | 491, param: .temperature))
        // Humidity invalid when any high byte is set.
        XCTAssertNil(AranetProtocol.scaled(0x0100, param: .humidity))
    }

    // MARK: - Current readings

    func testDecodeCurrentBasic() {
        // <HHHBBB: co2=637, temp=491, pressure=8384, humidity=33, battery=64, status=1
        let data = Data([0x7D, 0x02, 0xEB, 0x01, 0xC0, 0x20, 0x21, 0x40, 0x01])
        let reading = AranetProtocol.decodeCurrent(data)
        XCTAssertEqual(reading?.co2, 637)
        XCTAssertEqual(reading?.temperature ?? 0, 24.55, accuracy: 0.001)
        XCTAssertEqual(reading?.pressure ?? 0, 838.4, accuracy: 0.001)
        XCTAssertEqual(reading?.humidity, 33)
        XCTAssertEqual(reading?.battery, 64)
        XCTAssertNil(reading?.interval)
    }

    func testDecodeCurrentDetailed() {
        // Append interval=300, ago=50 for the detailed <HHHBBBHH layout.
        let data = Data([0x7D, 0x02, 0xEB, 0x01, 0xC0, 0x20, 0x21, 0x40, 0x01,
                         0x2C, 0x01, 0x32, 0x00])
        let reading = AranetProtocol.decodeCurrent(data)
        XCTAssertEqual(reading?.interval, 300)
        XCTAssertEqual(reading?.ago, 50)
    }

    func testDecodeCurrentTooShort() {
        XCTAssertNil(AranetProtocol.decodeCurrent(Data([0x00, 0x01, 0x02])))
    }

    // MARK: - History command

    func testHistoryCommand() {
        // Matches the documented example: CO2 (param 4) starting at index 478.
        let cmd = AranetProtocol.historyCommand(param: .co2, startIndex: 478)
        XCTAssertEqual([UInt8](cmd), [0x61, 0x04, 0xDE, 0x01])
    }

    func testHistoryCommandClampsZero() {
        let cmd = AranetProtocol.historyCommand(param: .temperature, startIndex: 0)
        XCTAssertEqual([UInt8](cmd), [0x61, 0x01, 0x01, 0x00])  // start clamped to 1
    }

    // MARK: - History packet parsing (matching param)

    func testParseHistoryPacketCO2() {
        // Header <BHHHHB: param=4, interval=300, total=1341, ago=10, start=478, count=2
        // then two CO2 values (H): 600, 605.
        let packet = Data([0x04, 0x2C, 0x01, 0x3D, 0x05, 0x0A, 0x00, 0xDE, 0x01, 0x02,
                           0x58, 0x02, 0x5D, 0x02])
        let parsed = AranetProtocol.parseHistoryPacket(packet, param: .co2)
        XCTAssertEqual(parsed?.0.param, 4)
        XCTAssertEqual(parsed?.0.start, 478)
        XCTAssertEqual(parsed?.0.count, 2)
        XCTAssertEqual(parsed?.1.compactMap { $0 }, [600, 605])
    }

    func testParseHistoryPacketHumidityIsSingleByte() {
        // Humidity values are 1 byte each.
        let packet = Data([0x02, 0x2C, 0x01, 0x3D, 0x05, 0x0A, 0x00, 0xDE, 0x01, 0x02,
                           0x21, 0x22])
        let parsed = AranetProtocol.parseHistoryPacket(packet, param: .humidity)
        XCTAssertEqual(parsed?.0.count, 2)
        XCTAssertEqual(parsed?.1.compactMap { $0 }, [33, 34])
    }

    func testParseHistoryPacketTooShort() {
        XCTAssertNil(AranetProtocol.parseHistoryPacket(Data([0x04, 0x00]), param: .co2))
    }
}
