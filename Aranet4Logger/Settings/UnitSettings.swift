import Foundation

/// Which sensor metric to surface directly in the menu bar title. `.none` keeps the plain
/// status icon (the previous behavior).
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case none
    case co2
    case temperature
    case humidity
    case pressure

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Icon only"
        case .co2: return "CO₂"
        case .temperature: return "Temperature"
        case .humidity: return "Humidity"
        case .pressure: return "Pressure"
        }
    }

    /// Format this metric's reading for the compact menu bar title, or `nil` if the relevant
    /// value is missing (`.none` is always `nil`). Stored values are °C / hPa.
    func menuBarText(
        co2: Int?,
        temperature: Double?,
        humidity: Double?,
        pressure: Double?,
        temperatureUnit: TemperatureUnit,
        pressureUnit: PressureUnit
    ) -> String? {
        switch self {
        case .none: return nil
        case .co2: return co2.map { "\($0)" }
        case .temperature: return temperature.map { temperatureUnit.format(celsius: $0) }
        case .humidity: return humidity.map { String(format: "%.0f%%", $0) }
        case .pressure: return pressure.map { pressureUnit.format(hPa: $0) }
        }
    }
}

/// Display unit for temperature. Data is always stored in °C; this only affects presentation.
enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .celsius: return "Celsius (°C)"
        case .fahrenheit: return "Fahrenheit (°F)"
        }
    }

    var symbol: String { self == .celsius ? "°C" : "°F" }

    /// Format a stored Celsius value in this unit.
    func format(celsius: Double) -> String {
        let value = self == .celsius ? celsius : celsius * 9.0 / 5.0 + 32.0
        return String(format: "%.1f%@", value, symbol)
    }

    /// Default based on the current locale's measurement system (US → Fahrenheit).
    static var localeDefault: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

/// Display unit for atmospheric pressure. Data is always stored in hPa.
enum PressureUnit: String, CaseIterable, Identifiable {
    case hectopascals
    case inchesOfMercury

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hectopascals: return "Hectopascals (hPa)"
        case .inchesOfMercury: return "Inches of mercury (inHg)"
        }
    }

    /// Format a stored hPa value in this unit.
    func format(hPa: Double) -> String {
        switch self {
        case .hectopascals: return String(format: "%.1f hPa", hPa)
        case .inchesOfMercury: return String(format: "%.2f inHg", hPa * 0.0295299830714)
        }
    }

    /// Default based on the current locale's measurement system (US → inHg).
    static var localeDefault: PressureUnit {
        Locale.current.measurementSystem == .us ? .inchesOfMercury : .hectopascals
    }
}
