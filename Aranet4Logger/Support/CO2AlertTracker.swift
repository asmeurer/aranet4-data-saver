import Foundation

/// Edge-triggered per-device high-CO₂ alert state. A notification should fire only when a
/// device's reading first crosses above the threshold; the alert re-arms once the reading
/// falls a hysteresis margin below the threshold, so values hovering around the threshold
/// don't fire repeatedly.
struct CO2AlertTracker {
    /// How far below the threshold a reading must fall before the alert re-arms (ppm).
    static let hysteresis = 100

    private var alerting: Set<String> = []

    /// Record a new reading. Returns true when this reading crosses above the threshold and a
    /// notification should fire.
    mutating func shouldAlert(device: String, co2: Int, threshold: Int) -> Bool {
        if alerting.contains(device) {
            if co2 <= threshold - Self.hysteresis {
                alerting.remove(device)
            }
            return false
        }
        if co2 >= threshold {
            alerting.insert(device)
            return true
        }
        return false
    }
}
