import Foundation

/// Minimal command-line interface, checked before the GUI launches.
///
///   Aranet4Logger --import <file.csv> --device <uuid>
///
/// Imports an official Aranet Home CSV export for the given device into the database, then
/// exits. Returns an exit code if a CLI command ran, or nil to continue to the GUI.
enum CLI {
    static func runIfRequested() -> Int32? {
        let args = CommandLine.arguments
        guard args.contains("--import") else { return nil }

        guard let file = value(for: "--import", in: args) else {
            FileHandle.standardError.write(Data("error: --import requires a file path\n".utf8))
            return 2
        }
        guard let device = value(for: "--device", in: args) else {
            FileHandle.standardError.write(Data("error: --import requires --device <uuid>\n".utf8))
            return 2
        }
        let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)

        var exitCode: Int32 = 0
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                let database = try Database()
                let result = try await CSVImporter.import(url: url, deviceID: device, database: database)
                let fmt = ISO8601DateFormatter()
                let range = "\(result.first.map { fmt.string(from: $0) } ?? "?") .. \(result.last.map { fmt.string(from: $0) } ?? "?")"
                print("Imported \(url.lastPathComponent) -> device \(device)")
                print("  parsed \(result.parsed) rows, inserted \(result.inserted) new (interval \(result.intervalSeconds)s)")
                print("  range \(range)")
            } catch {
                FileHandle.standardError.write(Data("import failed: \(error)\n".utf8))
                exitCode = 1
            }
            sem.signal()
        }
        sem.wait()
        return exitCode
    }

    private static func value(for flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
