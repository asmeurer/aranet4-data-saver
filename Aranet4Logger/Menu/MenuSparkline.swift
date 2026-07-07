import AppKit

/// The menu's inline charts: one compact sparkline row per metric, each rendered into an
/// NSImage shown as a menu item. A native `.menu`-style MenuBarExtra can't host live SwiftUI
/// views, and it scales any item image taller than 16 pt down to fit — so each row is a
/// 16 pt-tall image with the label drawn inside it. All colors are dynamic `NSColor`s and
/// the drawing handler re-runs on every draw, so rows re-resolve for the menu's light or
/// dark appearance for free.
enum MenuSparkline {
    /// One device's line within a row's plot.
    private struct Line {
        let color: NSColor
        /// Contiguous runs (split at data gaps) of (time fraction 0…1, converted value).
        let segments: [[(x: CGFloat, value: Double)]]
    }

    static let width: CGFloat = 300
    /// The tallest image a SwiftUI menu item displays unscaled.
    static let height: CGFloat = 16
    /// Label column; the plot fills the rest of the row.
    private static let labelWidth: CGFloat = 124

    /// Render one metric's sparkline row for the given device series (the menu model's
    /// last-24-hours window), or nil when no device has data for the metric. Values are
    /// converted to display units up front, so the handler redraws from plain numbers.
    static func rowImage(
        metric: ChartMetric,
        series: [ChartsModel.DeviceSeries],
        temperatureUnit: TemperatureUnit,
        pressureUnit: PressureUnit,
        co2Threshold: Int,
        span: TimeInterval,
        maxGap: TimeInterval
    ) -> NSImage? {
        let end = Date()
        let start = end.addingTimeInterval(-span)

        var lines: [Line] = []
        var allValues: [Double] = []
        for device in series {
            let points = device.points.filter { point in
                point.timestamp >= start && point.timestamp <= end
            }.compactMap { point in
                metric.value(
                    from: point, temperatureUnit: temperatureUnit, pressureUnit: pressureUnit
                ).map { MetricPoint(date: point.timestamp, value: $0) }
            }
            guard !points.isEmpty else { continue }
            allValues.append(contentsOf: points.map(\.value))
            let segments = contiguousSegments(of: points, maxGap: maxGap).map { segment in
                segment.map { point in
                    (x: CGFloat(point.date.timeIntervalSince(start) / span), value: point.value)
                }
            }
            lines.append(Line(color: ChartPalette.seriesNSColor(device.slot), segments: segments))
        }
        guard let dataMin = allValues.min(), let dataMax = allValues.max() else { return nil }

        let label = "\(metric.menuLabel)  \(metric.format(dataMin, pressureUnit: pressureUnit))–"
            + metric.format(dataMax, pressureUnit: pressureUnit)

        // Same visibility rule as the Charts window: a threshold only appears once the data
        // reaches it, so a calm day isn't rescaled just to show a far-away red line.
        var thresholds: [(value: Double, color: NSColor)] = []
        if metric == .co2 {
            let threshold = SettingsKeys.clampedCO2Threshold(co2Threshold)
            if threshold > 1000, dataMax >= 1000 {
                thresholds.append((value: 1000, color: ChartPalette.warningNSColor))
            }
            if dataMax >= Double(threshold) {
                thresholds.append((value: Double(threshold), color: ChartPalette.criticalNSColor))
            }
        }

        return image(label: label, lines: lines, thresholds: thresholds)
    }

    // MARK: - Drawing (flipped coordinates: y grows downward)

    private static func image(
        label: String,
        lines: [Line],
        thresholds: [(value: Double, color: NSColor)]
    ) -> NSImage {
        NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            let text = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            text.draw(at: NSPoint(x: 0, y: (height - text.size().height) / 2))

            let plotLeft = max(labelWidth, text.size().width + 10)
            let plotWidth = width - plotLeft
            // Keep round line caps inside the image so extremes aren't clipped flat.
            let plotTop: CGFloat = 1.5
            let plotHeight = height - 3

            // Y-domain across every line plus any visible threshold; a flat line gets an
            // artificial ±1 so it draws mid-plot.
            let values = lines.flatMap { $0.segments.flatMap { $0.map(\.value) } }
                + thresholds.map(\.value)
            var minValue = values.min() ?? 0
            var maxValue = values.max() ?? 1
            if minValue == maxValue {
                minValue -= 1
                maxValue += 1
            }
            func yFor(_ value: Double) -> CGFloat {
                plotTop + plotHeight * CGFloat(1 - (value - minValue) / (maxValue - minValue))
            }
            func xFor(_ fraction: CGFloat) -> CGFloat {
                plotLeft + fraction * plotWidth
            }

            for threshold in thresholds {
                let path = NSBezierPath()
                path.lineWidth = 1
                let y = yFor(threshold.value)
                path.move(to: NSPoint(x: plotLeft, y: y))
                path.line(to: NSPoint(x: width, y: y))
                threshold.color.withAlphaComponent(0.6).setStroke()
                path.stroke()
            }

            for line in lines {
                line.color.setStroke()
                for segment in line.segments {
                    guard let first = segment.first else { continue }
                    if segment.count == 1 {
                        // A lone point (isolated bucket) strokes nothing; mark it as a dot.
                        line.color.setFill()
                        NSBezierPath(ovalIn: NSRect(
                            x: xFor(first.x) - 1.25, y: yFor(first.value) - 1.25,
                            width: 2.5, height: 2.5
                        )).fill()
                        continue
                    }
                    let path = NSBezierPath()
                    path.lineWidth = 1.25
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.move(to: NSPoint(x: xFor(first.x), y: yFor(first.value)))
                    for point in segment.dropFirst() {
                        path.line(to: NSPoint(x: xFor(point.x), y: yFor(point.value)))
                    }
                    path.stroke()
                }
            }
            return true
        }
    }
}
