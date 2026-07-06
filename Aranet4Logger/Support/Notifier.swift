import Foundation
import UserNotifications

/// Posts high-CO₂ user notifications. Also acts as the notification-center delegate so
/// banners are shown even while the app is frontmost (e.g. with the Settings window open).
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Install as the notification-center delegate. Call once at startup.
    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Ask the user for notification permission; returns whether alerts are allowed.
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            AppLog.shared.error("Notification authorization failed: \(error)")
            return false
        }
    }

    /// Post a high-CO₂ alert for a device. One identifier per device, so a newer alert
    /// replaces a still-visible older one instead of stacking.
    func postHighCO2(deviceID: String, deviceName: String, co2: Int, threshold: Int) {
        let content = UNMutableNotificationContent()
        content.title = "High CO₂ — \(deviceName)"
        content.body = "\(co2) ppm (warning threshold \(threshold) ppm)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "co2-high-\(deviceID)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLog.shared.error("Failed to post CO₂ notification: \(error)")
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
