import Foundation
import XCTest

final class CO2AlertTrackerTests: XCTestCase {
    func testAlertsOnceWhenCrossingThreshold() {
        var tracker = CO2AlertTracker()
        XCTAssertFalse(tracker.shouldAlert(device: "a", co2: 900, threshold: 1400))
        XCTAssertTrue(tracker.shouldAlert(device: "a", co2: 1500, threshold: 1400))
        // Still high: no repeat alert.
        XCTAssertFalse(tracker.shouldAlert(device: "a", co2: 1600, threshold: 1400))
        XCTAssertFalse(tracker.shouldAlert(device: "a", co2: 1450, threshold: 1400))
    }

    func testAlertsAtExactThreshold() {
        var tracker = CO2AlertTracker()
        XCTAssertTrue(tracker.shouldAlert(device: "a", co2: 1400, threshold: 1400))
    }

    func testHysteresisPreventsFlapping() {
        var tracker = CO2AlertTracker()
        XCTAssertTrue(tracker.shouldAlert(device: "a", co2: 1400, threshold: 1400))
        // Dips below the threshold but within the hysteresis band: stays armed-off.
        XCTAssertFalse(tracker.shouldAlert(device: "a", co2: 1350, threshold: 1400))
        XCTAssertFalse(tracker.shouldAlert(device: "a", co2: 1410, threshold: 1400))
        // Falls a full hysteresis margin below: re-arms...
        XCTAssertFalse(tracker.shouldAlert(device: "a", co2: 1300, threshold: 1400))
        // ...so the next crossing alerts again.
        XCTAssertTrue(tracker.shouldAlert(device: "a", co2: 1400, threshold: 1400))
    }

    func testDevicesTrackedIndependently() {
        var tracker = CO2AlertTracker()
        XCTAssertTrue(tracker.shouldAlert(device: "a", co2: 1500, threshold: 1400))
        XCTAssertTrue(tracker.shouldAlert(device: "b", co2: 1500, threshold: 1400))
        XCTAssertFalse(tracker.shouldAlert(device: "a", co2: 1500, threshold: 1400))
    }
}
