import Foundation
import os

/// Filesystem locations and a simple file logger. Everything lives under
/// ~/Library/Application Support/Aranet4Logger/.
enum AppPaths {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Aranet4Logger", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var config: URL { directory.appendingPathComponent("config.json") }
    static var database: URL { directory.appendingPathComponent("aranet.sqlite") }
    static var logFile: URL { directory.appendingPathComponent("aranet.log") }
}

/// Lightweight logger that writes timestamped lines to both the unified log and aranet.log.
/// Errors are always recorded with full detail (no silent swallowing).
final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    private let logger = Logger(subsystem: "com.asmeurer.Aranet4Logger", category: "app")
    private let queue = DispatchQueue(label: "com.asmeurer.Aranet4Logger.log")
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        write("INFO", message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        write("ERROR", message)
    }

    private func write(_ level: String, _ message: String) {
        let line = "\(dateFormatter.string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            let url = AppPaths.logFile
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
