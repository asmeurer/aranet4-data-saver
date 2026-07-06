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
