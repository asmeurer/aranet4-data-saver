import SwiftUI

/// Custom entry point: run a CLI command (e.g. `--import`) and exit if requested, otherwise
/// launch the menu bar app.
@main
struct Main {
    static func main() {
        if let code = CLI.runIfRequested() {
            exit(code)
        }
        Aranet4LoggerApp.main()
    }
}

struct Aranet4LoggerApp: App {
    @State private var coordinator = AppCoordinatorHolder()

    var body: some Scene {
        MenuBarExtra {
            MenuView(
                appState: coordinator.coordinator.appState,
                updater: coordinator.updater,
                onSyncNow: { coordinator.coordinator.syncNow() },
                onToggleLogin: { enabled in
                    LoginItemManager.setEnabled(enabled)
                    coordinator.coordinator.appState.launchAtLogin = LoginItemManager.isEnabled
                },
                onImportCSV: { deviceID, url in
                    coordinator.coordinator.importCSV(url: url, deviceID: deviceID)
                }
            )
        } label: {
            MenuBarLabel(appState: coordinator.coordinator.appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                appState: coordinator.coordinator.appState,
                onRename: { id, name in coordinator.coordinator.rename(deviceID: id, to: name) }
            )
        }
    }
}

/// Holds the single Coordinator and starts it once. `@State` keeps it alive for the app
/// lifetime; the Coordinator is `@MainActor`, matching SwiftUI's main-actor scenes.
@MainActor
@Observable
final class AppCoordinatorHolder {
    let coordinator: Coordinator
    let updater: UpdaterManager

    init() {
        coordinator = Coordinator()
        coordinator.start()
        coordinator.appState.launchAtLogin = LoginItemManager.isEnabled
        updater = UpdaterManager()
    }
}
