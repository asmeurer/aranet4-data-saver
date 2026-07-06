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
        // MenuBarMetric raw values are persisted too.
        XCTAssertEqual(MenuBarMetric.none.rawValue, "none")
        XCTAssertEqual(MenuBarMetric.co2.rawValue, "co2")
        XCTAssertEqual(MenuBarMetric.temperature.rawValue, "temperature")
        XCTAssertEqual(MenuBarMetric.humidity.rawValue, "humidity")
        XCTAssertEqual(MenuBarMetric.pressure.rawValue, "pressure")
    }

    func testMenuBarParts() {
        func parts(_ metric: MenuBarMetric) -> (value: String, unit: String)? {
            metric.menuBarParts(
                co2: 812, temperature: 24.5, humidity: 47.4, pressure: 838.4,
                temperatureUnit: .celsius, pressureUnit: .hectopascals
            )
        }
        XCTAssertNil(parts(.none))
        XCTAssertEqual(parts(.co2)?.value, "812")
        XCTAssertEqual(parts(.co2)?.unit, "ppm")
        XCTAssertEqual(parts(.temperature)?.value, "24.5")
        XCTAssertEqual(parts(.temperature)?.unit, "°C")
        XCTAssertEqual(parts(.humidity)?.value, "47")
        XCTAssertEqual(parts(.humidity)?.unit, "%")
        XCTAssertEqual(parts(.pressure)?.value, "838.4")
        XCTAssertEqual(parts(.pressure)?.unit, "hPa")
        // Selected units are honored.
        let fahrenheit = MenuBarMetric.temperature.menuBarParts(
            co2: nil, temperature: 0, humidity: nil, pressure: nil,
            temperatureUnit: .fahrenheit, pressureUnit: .hectopascals
        )
        XCTAssertEqual(fahrenheit?.value, "32.0")
        XCTAssertEqual(fahrenheit?.unit, "°F")
    }

    func testMenuBarPartsMissingValuesAreNil() {
        let empty = MenuBarMetric.co2.menuBarParts(
            co2: nil, temperature: nil, humidity: nil, pressure: nil,
            temperatureUnit: .celsius, pressureUnit: .hectopascals
        )
        XCTAssertNil(empty)
    }
}
