import AppKit
import SwiftUI

/// A small About window with the app icon, version, and project links. A custom window (not
/// `orderFrontStandardAboutPanel`) so it can carry the website/GitHub links and be raised
/// reliably from this LSUIElement app via `WindowFronter`.
struct AboutView: View {
    static let windowID = "about"

    static let websiteURL = URL(string: "https://asmeurer.github.io/aranet4-data-saver/")!
    static let repoURL = URL(string: "https://github.com/asmeurer/aranet4-data-saver")!

    /// The build's marketing version (set from the release tag by CI).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Aranet4 Logger")
                .font(.title2.bold())
            Text("Version \(Self.version)")
                .foregroundStyle(.secondary)
            Text("Continuously logs Aranet4 air-quality sensors\nto a local SQLite database.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 20) {
                Link("Website", destination: Self.websiteURL)
                Link("GitHub", destination: Self.repoURL)
            }
            .padding(.top, 2)
            Text("MIT License · © 2025–2026 Aaron Meurer")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 320)
        .background(WindowCapture(WindowFronter.about))
    }
}
