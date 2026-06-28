import AppKit
import SwiftUI

/// Helps this menu bar (`LSUIElement`) app reliably raise its Settings window.
///
/// Accessory apps have no Dock icon and their windows don't participate in normal window
/// management, so once the Settings window falls behind another app it's awkward to recover.
/// SwiftUI's `openSettings` / `SettingsLink` won't re-front an already-open window that's
/// buried — `orderFrontRegardless()` is what actually raises a window when the app isn't the
/// active one. We capture the real `NSWindow` (rather than relying on an undocumented window
/// identifier) so fronting keeps working across macOS releases.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private weak var window: NSWindow?

    func capture(_ window: NSWindow?) {
        if let window { self.window = window }
    }

    /// Bring the app forward and raise the Settings window above other apps' windows.
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

/// Captures the hosting `NSWindow` of the Settings view into `SettingsWindowController`.
/// Added as a `.background` of `SettingsView`.
struct SettingsWindowCapture: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { SettingsWindowController.shared.capture(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { SettingsWindowController.shared.capture(nsView.window) }
    }
}
