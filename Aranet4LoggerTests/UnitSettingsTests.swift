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

    func testMenuBarText() {
        func text(_ metric: MenuBarMetric) -> String? {
            metric.menuBarText(
                co2: 812, temperature: 24.5, humidity: 47.4, pressure: 838.4,
                temperatureUnit: .celsius, pressureUnit: .hectopascals
            )
        }
        XCTAssertNil(text(.none))
        XCTAssertEqual(text(.co2), "812")
        XCTAssertEqual(text(.temperature), "24.5°C")
        XCTAssertEqual(text(.humidity), "47%")
        XCTAssertEqual(text(.pressure), "838.4 hPa")
        // Selected units are honored.
        XCTAssertEqual(
            MenuBarMetric.temperature.menuBarText(
                co2: nil, temperature: 0, humidity: nil, pressure: nil,
                temperatureUnit: .fahrenheit, pressureUnit: .hectopascals
            ),
            "32.0°F"
        )
    }

    func testMenuBarTextMissingValuesAreNil() {
        let empty = MenuBarMetric.co2.menuBarText(
            co2: nil, temperature: nil, humidity: nil, pressure: nil,
            temperatureUnit: .celsius, pressureUnit: .hectopascals
        )
        XCTAssertNil(empty)
    }
}
