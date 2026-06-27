import Foundation
import XCTest

final class UnitSettingsTests: XCTestCase {
    func testTemperatureFormatting() {
        XCTAssertEqual(TemperatureUnit.celsius.format(celsius: 24.5), "24.5°C")
        // 24.55 °C == 76.19 °F → rounded to one place "76.2°F".
        XCTAssertEqual(TemperatureUnit.fahrenheit.format(celsius: 24.55), "76.2°F")
        XCTAssertEqual(TemperatureUnit.fahrenheit.format(celsius: 0), "32.0°F")
        XCTAssertEqual(TemperatureUnit.fahrenheit.format(celsius: 100), "212.0°F")
    }

    func testPressureFormatting() {
        XCTAssertEqual(PressureUnit.hectopascals.format(hPa: 838.4), "838.4 hPa")
        // 1013.25 hPa == 29.92 inHg.
        XCTAssertEqual(PressureUnit.inchesOfMercury.format(hPa: 1013.25), "29.92 inHg")
    }

    func testRawValuesAreStable() {
        // @AppStorage persists these raw values; they must not change.
        XCTAssertEqual(TemperatureUnit.celsius.rawValue, "celsius")
        XCTAssertEqual(TemperatureUnit.fahrenheit.rawValue, "fahrenheit")
        XCTAssertEqual(PressureUnit.hectopascals.rawValue, "hectopascals")
        XCTAssertEqual(PressureUnit.inchesOfMercury.rawValue, "inchesOfMercury")
    }
}
