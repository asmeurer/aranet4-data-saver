import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` to register/unregister the app as a login item.
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            AppLog.shared.info("Login item \(enabled ? "enabled" : "disabled")")
        } catch {
            AppLog.shared.error("Failed to update login item: \(error)")
        }
    }
}
