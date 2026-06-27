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
}
