import Charts
import SwiftUI

/// The Charts window: stored history for every configured sensor, drawn as one line chart
/// per metric (small multiples — CO₂, temperature, humidity, pressure each get their own
/// axis; two measures never share a plot). A single filter row above the charts scopes the
/// time range for all of them, and its per-device toggles double as the legend. Hovering a
/// chart shows a crosshair with every device's value at that time; a min/avg/max line under
/// each title keeps the numbers readable without hovering.
struct ChartsView: View {
    static let windowID = "charts"

    @Bindable var model: ChartsModel

    @AppStorage(SettingsKeys.temperatureUnit) private var temperatureUnit = TemperatureUnit.localeDefault
    @AppStorage(SettingsKeys.pressureUnit) private var pressureUnit = PressureUnit.localeDefault
    @AppStorage(SettingsKeys.co2Threshold) private var co2Threshold = SettingsKeys.defaultCO2Threshold

    var body: some View {
        VStack(spacing: 0) {
            filterRow
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            if let message = model.errorMessage {
                ContentUnavailableView(
                    "Couldn't load history",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxHeight: .infinity)
            } else if model.series.allSatisfy({ $0.points.isEmpty }) {
                ContentUnavailableView(
                    "No readings in this range",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Data appears here as your sensors sync.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        ForEach(ChartMetric.allCases, id: \.self) { metric in
                            MetricChart(
                                title: metric.title(
                                    temperatureUnit: temperatureUnit, pressureUnit: pressureUnit
                                ),
                                rows: rows(for: metric),
                                thresholds: thresholds(for: metric),
                                pointSpacing: TimeInterval(model.bucketSeconds),
                                xDomain: model.zoomDomain,
                                format: { metric.format($0, pressureUnit: pressureUnit) },
                                onZoom: { model.zoom(to: $0) },
                                onResetZoom: { model.resetZoom() }
                            )
                        }
                    }
                    .padding(16)
                }
                // Floats over the charts instead of living in the filter row, which is
                // already full at the default window width.
                .overlay(alignment: .topTrailing) {
                    if model.zoomDomain != nil {
                        Button("Reset Zoom", systemImage: "arrow.down.backward.and.arrow.up.forward") {
                            model.resetZoom()
                        }
                        .buttonStyle(.bordered)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 10)
                        .padding(.trailing, 16)
                        .help("Show the whole range again (or double-click a chart)")
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(WindowCapture(.charts))
        .onAppear { model.reload() }
        .onChange(of: totalStored) { model.reload() }
    }

    /// Reload trigger: grows whenever any device stores new readings.
    private var totalStored: Int {
        model.appState.devices.reduce(0) { $0 + $1.storedCount }
    }

    // MARK: - Filter row (time range + device visibility, shared by all charts)

    private var filterRow: some View {
        HStack(spacing: 16) {
            Picker("Range", selection: $model.range) {
                ForEach(ChartTimeRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            ForEach(model.series) { series in
                legendToggle(series)
            }
        }
    }

    private func legendToggle(_ series: ChartsModel.DeviceSeries) -> some View {
        let hidden = model.hiddenDeviceIDs.contains(series.id)
        return Button {
            model.toggleVisibility(series.id)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(ChartPalette.series(series.slot))
                    .frame(width: 9, height: 9)
                Text(series.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .fixedSize()
            .opacity(hidden ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .help(hidden ? "Show \(series.name)" : "Hide \(series.name)")
    }

    // MARK: - Per-metric plumbing (units are display-only; storage is °C / hPa)

    private func rows(for metric: ChartMetric) -> [MetricChart.SeriesRow] {
        model.visibleSeries.map { series in
            let points = series.points.compactMap { point in
                metric.value(
                    from: point, temperatureUnit: temperatureUnit, pressureUnit: pressureUnit
                ).map { MetricPoint(date: point.timestamp, value: $0) }
            }
            return MetricChart.SeriesRow(
                id: series.id,
                name: series.name,
                color: ChartPalette.series(series.slot),
                points: points,
                segments: contiguousSegments(of: points, maxGap: model.maxGap)
            )
        }
    }

    /// CO₂ gets status-colored threshold rules: Aranet's yellow zone at 1000 ppm, and the
    /// alert threshold configured in Settings in red. The other metrics have no fixed levels.
    private func thresholds(for metric: ChartMetric) -> [MetricChart.Threshold] {
        guard metric == .co2 else { return [] }
        let threshold = SettingsKeys.clampedCO2Threshold(co2Threshold)
        var result: [MetricChart.Threshold] = []
        if threshold > 1000 {
            result.append(MetricChart.Threshold(value: 1000, label: "1000", color: ChartPalette.warning))
        }
        result.append(MetricChart.Threshold(
            value: Double(threshold), label: "\(threshold)", color: ChartPalette.critical
        ))
        return result
    }
}

/// One metric's chart card: title, per-device min/avg/max summary, and the line chart with
/// a hover crosshair.
private struct MetricChart: View {
    struct SeriesRow: Identifiable {
        let id: String
        let name: String
        let color: Color
        /// All points, time-ordered (for stats and nearest-point lookup).
        let points: [MetricPoint]
        /// The same points split at data gaps, so lines don't bridge downtime.
        let segments: [[MetricPoint]]
    }

    struct Threshold: Identifiable {
        let value: Double
        let label: String
        let color: Color
        var id: Double { value }
    }

    let title: String
    let rows: [SeriesRow]
    let thresholds: [Threshold]
    /// Time between consecutive points (the aggregation bucket width).
    let pointSpacing: TimeInterval
    /// Explicit x-domain while zoomed in, or nil to fit the loaded data.
    let xDomain: ClosedRange<Date>?
    let format: (Double) -> String
    /// Zoom into a drag-selected time window (shared across all the charts).
    let onZoom: (ClosedRange<Date>) -> Void
    /// Reset zoom on double-click.
    let onResetZoom: () -> Void

    @State private var selectedDate: Date?
    /// Plot-space x positions of an in-progress zoom drag (anchor may be right of current).
    @State private var dragSelection: (anchor: CGFloat, current: CGFloat)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            summaryRow
            if rows.allSatisfy({ $0.points.isEmpty }) {
                Text("No data in this range")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 170)
            } else {
                chart
                    .frame(height: 170)
            }
        }
    }

    /// Values-without-hovering: each device's range and mean over the visible window.
    private var summaryRow: some View {
        HStack(spacing: 16) {
            ForEach(rows) { row in
                if let stats = stats(row) {
                    let summary = "\(format(stats.min))–\(format(stats.max)), avg \(format(stats.mean))"
                    HStack(spacing: 5) {
                        Circle()
                            .fill(row.color)
                            .frame(width: 8, height: 8)
                        Text("\(row.name)  \(summary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private struct Stats {
        var min: Double
        var max: Double
        var mean: Double
    }

    private func stats(_ row: SeriesRow) -> Stats? {
        let values = row.points.map(\.value)
        guard let min = values.min(), let max = values.max() else { return nil }
        return Stats(min: min, max: max, mean: values.reduce(0, +) / Double(values.count))
    }

    @ViewBuilder
    private var chart: some View {
        // The zoomed domain is set explicitly so all four charts stay in exact sync even
        // when a device has no data at the window's edges.
        if let xDomain {
            chartBase.chartXScale(domain: xDomain)
        } else {
            chartBase
        }
    }

    private var chartBase: some View {
        Chart {
            ForEach(rows) { row in
                ForEach(Array(row.segments.enumerated()), id: \.offset) { index, segment in
                    ForEach(segment) { point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value(title, point.value),
                            series: .value("Series", "\(row.id)#\(index)")
                        )
                        .foregroundStyle(by: .value("Device", row.name))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
            }

            ForEach(visibleThresholds) { threshold in
                RuleMark(y: .value("Threshold", threshold.value))
                    .foregroundStyle(threshold.color.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    // Leading, away from the trailing y-axis tick labels; kept inside the
                    // plot area so the label isn't clipped at the edge.
                    .annotation(
                        position: .topLeading,
                        spacing: 2,
                        overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))
                    ) {
                        Text(threshold.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }

            // The crosshair pauses while a rubber-band zoom drag is in progress.
            if let selection, dragSelection == nil {
                RuleMark(x: .value("Time", selection.date))
                    .foregroundStyle(.quaternary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        tooltip(selection)
                    }
                ForEach(selection.values, id: \.row.id) { value in
                    PointMark(
                        x: .value("Time", value.point.date),
                        y: .value(title, value.point.value)
                    )
                    .symbol {
                        // A surface-colored ring keeps the marker legible on the lines.
                        ZStack {
                            Circle().fill(.background).frame(width: 13, height: 13)
                            Circle().fill(value.row.color).frame(width: 9, height: 9)
                        }
                    }
                }
            }
        }
        .chartForegroundStyleScale(domain: rows.map(\.name), range: rows.map(\.color))
        .chartLegend(.hidden)  // the filter row's device toggles are the legend
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            // Recessive solid hairlines (the default date axis draws dashed gridlines).
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.quaternary)
                AxisTick()
                AxisValueLabel()
            }
        }
        // Hover and gestures are handled by a plot-area overlay instead of chartXSelection:
        // the built-in selection scrubbing would otherwise consume the zoom drag.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotAnchor = proxy.plotFrame {
                    let plot = geometry[plotAnchor]
                    // Hover drives the crosshair; dragging rubber-bands a zoom window;
                    // double-click zooms back out.
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(width: plot.width, height: plot.height)
                        .offset(x: plot.minX, y: plot.minY)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                selectedDate = proxy.value(atX: location.x)
                            case .ended:
                                selectedDate = nil
                            }
                        }
                        .onTapGesture(count: 2) { onResetZoom() }
                        .gesture(zoomDrag(proxy: proxy, plotWidth: plot.width))
                    // The rubber band for an in-progress zoom drag.
                    if let dragSelection {
                        let lower = max(min(dragSelection.anchor, dragSelection.current), 0)
                        let upper = min(
                            max(dragSelection.anchor, dragSelection.current), plot.width
                        )
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.12))
                            .border(Color.accentColor.opacity(0.4), width: 1)
                            .frame(width: max(upper - lower, 1), height: plot.height)
                            .offset(x: plot.minX + lower, y: plot.minY)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    /// Drag horizontally across the plot to zoom into the selected time window.
    private func zoomDrag(proxy: ChartProxy, plotWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                dragSelection = (anchor: value.startLocation.x, current: value.location.x)
            }
            .onEnded { value in
                defer { dragSelection = nil }
                let lower = max(min(value.startLocation.x, value.location.x), 0)
                let upper = min(max(value.startLocation.x, value.location.x), plotWidth)
                guard let start: Date = proxy.value(atX: lower),
                      let end: Date = proxy.value(atX: upper),
                      start < end else { return }
                onZoom(start...end)
            }
    }

    /// Thresholds only appear once the data reaches them, so a calm week isn't rescaled
    /// just to show a red line far above the traces.
    private var visibleThresholds: [Threshold] {
        let dataMax = rows.flatMap { $0.points.map(\.value) }.max() ?? .leastNonzeroMagnitude
        return thresholds.filter { $0.value <= dataMax }
    }

    // MARK: - Hover selection

    private struct Selection {
        var date: Date
        var values: [(row: SeriesRow, point: MetricPoint)]
    }

    /// The hover position snapped to the nearest stored point, with each device's value in
    /// the same bucket (a device inside a data gap is omitted rather than shown with a
    /// far-away value).
    private var selection: Selection? {
        guard let selectedDate else { return nil }
        func distance(_ point: MetricPoint) -> TimeInterval {
            abs(point.date.timeIntervalSince(selectedDate))
        }
        let candidates = rows.compactMap { row in
            row.points.min { distance($0) < distance($1) }.map { (row: row, point: $0) }
        }
        guard let nearest = candidates.min(by: { distance($0.point) < distance($1.point) })
        else { return nil }
        let date = nearest.point.date
        let values = candidates.filter { abs($0.point.date.timeIntervalSince(date)) < pointSpacing / 2 }
        return Selection(date: date, values: values)
    }

    private func tooltip(_ selection: Selection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selection.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(selection.values, id: \.row.id) { value in
                HStack(spacing: 5) {
                    Circle()
                        .fill(value.row.color)
                        .frame(width: 8, height: 8)
                    Text(value.row.name)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(format(value.point.value))
                        .fontWeight(.medium)
                }
                .font(.caption)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
