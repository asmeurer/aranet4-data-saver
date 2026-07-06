import AppKit
import SwiftUI

/// Helps this menu bar (`LSUIElement`) app reliably raise its windows.
///
/// Accessory apps have no Dock icon and their windows don't participate in normal window
/// management, so once a window falls behind another app it's awkward to recover. SwiftUI's
/// `openSettings` / `openWindow` won't re-front an already-open window that's buried —
/// `orderFrontRegardless()` is what actually raises a window when the app isn't the active
/// one. We capture the real `NSWindow` (rather than relying on an undocumented window
/// identifier) so fronting keeps working across macOS releases. One instance per window.
@MainActor
final class WindowFronter {
    static let settings = WindowFronter()
    static let charts = WindowFronter()

    private weak var window: NSWindow?

    func capture(_ window: NSWindow?) {
        if let window { self.window = window }
    }

    /// Bring the app forward and raise the window above other apps' windows.
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

/// Captures the hosting `NSWindow` of a view into a `WindowFronter`. Added as a
/// `.background` of the window's root view.
struct WindowCapture: NSViewRepresentable {
    let fronter: WindowFronter

    init(_ fronter: WindowFronter) {
        self.fronter = fronter
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [fronter] in fronter.capture(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [fronter] in fronter.capture(nsView.window) }
    }
}
