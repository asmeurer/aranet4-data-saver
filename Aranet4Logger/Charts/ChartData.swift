import Foundation

/// Preset time ranges for the Charts window, shown as a segmented control above the charts.
enum ChartTimeRange: String, CaseIterable, Identifiable {
    case day
    case threeDays
    case week
    case month
    case threeMonths
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "Day"
        case .threeDays: return "3 Days"
        case .week: return "Week"
        case .month: return "Month"
        case .threeMonths: return "3 Months"
        case .all: return "All"
        }
    }

    /// Span in seconds, or `nil` for the full stored history.
    var duration: TimeInterval? {
        switch self {
        case .day: return 86_400
        case .threeDays: return 3 * 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .threeMonths: return 90 * 86_400
        case .all: return nil
        }
    }

    /// Aggregation bucket width for a chart spanning `span` seconds: targets ~300 points per
    /// series, snapped up to the sensors' 5-minute sample grid.
    static func bucketSeconds(spanning span: TimeInterval) -> Int {
        let grid = 300.0
        let target = span / 300.0   // desired bucket width for ~300 buckets
        return max(Int(grid), Int((target / grid).rounded(.up)) * Int(grid))
    }
}

/// The four charted metrics, in display order — shared by the Charts window and the menu's
/// inline sparklines. Units are display-only; storage is always °C / hPa.
enum ChartMetric: CaseIterable {
    case co2
    case temperature
    case humidity
    case pressure

    /// Short name for the menu's sparkline rows, where space is tight.
    var menuLabel: String {
        switch self {
        case .co2: return "CO₂"
        case .temperature: return "Temp"
        case .humidity: return "Humidity"
        case .pressure: return "Pressure"
        }
    }

    /// Chart title including the display unit.
    func title(temperatureUnit: TemperatureUnit, pressureUnit: PressureUnit) -> String {
        switch self {
        case .co2: return "CO₂ (ppm)"
        case .temperature: return "Temperature (\(temperatureUnit.symbol))"
        case .humidity: return "Relative humidity (%)"
        case .pressure: return "Pressure (\(pressureUnit.symbol))"
        }
    }

    /// This metric's value from a history point, converted to the display unit.
    func value(
        from point: HistoryPoint, temperatureUnit: TemperatureUnit, pressureUnit: PressureUnit
    ) -> Double? {
        switch self {
        case .co2: return point.co2
        case .temperature: return point.temperature.map { temperatureUnit.convert(celsius: $0) }
        case .humidity: return point.humidity
        case .pressure: return point.pressure.map { pressureUnit.convert(hPa: $0) }
        }
    }

    /// Format an already-converted value with this metric's precision.
    func format(_ value: Double, pressureUnit: PressureUnit) -> String {
        let digits: Int
        switch self {
        case .co2, .humidity: digits = 0
        case .temperature: digits = 1
        case .pressure: digits = pressureUnit == .hectopascals ? 1 : 2
        }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }
}

/// One metric value at one time, extracted from a `HistoryPoint` for plotting.
struct MetricPoint: Identifiable, Equatable {
    var date: Date
    var value: Double
    var id: Date { date }
}

/// Split a time-ordered series into contiguous runs, breaking wherever consecutive points
/// are more than `maxGap` apart — so a line doesn't bridge hours when a device was
/// unreachable or the app wasn't running.
func contiguousSegments(of points: [MetricPoint], maxGap: TimeInterval) -> [[MetricPoint]] {
    var segments: [[MetricPoint]] = []
    var current: [MetricPoint] = []
    for point in points {
        if let last = current.last, point.date.timeIntervalSince(last.date) > maxGap {
            segments.append(current)
            current = []
        }
        current.append(point)
    }
    if !current.isEmpty { segments.append(current) }
    return segments
}
