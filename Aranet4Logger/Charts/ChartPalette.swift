import AppKit
import SwiftUI

/// Colors for the Charts window. Each series slot is a light/dark pair resolved dynamically
/// through `NSColor`, so charts adapt when the system appearance changes. Slots are assigned
/// to devices in config order and stay fixed — hiding one device never recolors the others.
///
/// The values are a colorblind-safe categorical palette validated for both surfaces
/// (adjacent-pair CVD ΔE and ≥3:1 contrast, checked per mode).
enum ChartPalette {
    /// Categorical series slots (light, dark), in fixed assignment order.
    private static let slots: [(light: String, dark: String)] = [
        ("#2a78d6", "#3987e5"),  // blue
        ("#1baf7a", "#199e70"),  // aqua
        ("#eda100", "#c98500"),  // yellow
        ("#008300", "#008300"),  // green
        ("#4a3aa7", "#9085e9"),  // violet
        ("#e34948", "#e66767"),  // red
        ("#e87ba4", "#d55181"),  // magenta
        ("#eb6834", "#d95926"),  // orange
    ]

    static func series(_ slot: Int) -> Color {
        Color(nsColor: seriesNSColor(slot))
    }

    /// AppKit flavor of `series(_:)`, for Core Graphics drawing (the menu sparkline image).
    static func seriesNSColor(_ slot: Int) -> NSColor {
        dynamic(slots[slot % slots.count])
    }

    /// CO₂ threshold rules (status colors, never used for a series). The light-mode warning
    /// step is darkened so a hairline rule stays visible on the light surface.
    static let warning = Color(nsColor: warningNSColor)
    static let critical = Color(nsColor: criticalNSColor)
    static let warningNSColor = dynamic(("#b97900", "#fab219"))
    static let criticalNSColor = dynamic(("#d03b3b", "#d03b3b"))

    private static func dynamic(_ pair: (light: String, dark: String)) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? pair.dark : pair.light)
        }
    }
}

private extension NSColor {
    /// From a "#rrggbb" string in sRGB. Input is trusted (compile-time constants above).
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
