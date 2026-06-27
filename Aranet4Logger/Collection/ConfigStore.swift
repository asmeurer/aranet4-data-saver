import Foundation

/// Loads and persists `AppConfig` as JSON in Application Support. On first run it writes the
/// default config (prefilled with the two known devices).
enum ConfigStore {
    static func load() -> AppConfig {
        let url = AppPaths.config
        guard let data = try? Data(contentsOf: url) else {
            let config = AppConfig.default
            save(config)
            return config
        }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            AppLog.shared.error("Failed to decode config, using defaults: \(error)")
            return AppConfig.default
        }
    }

    static func save(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(config)
            try data.write(to: AppPaths.config, options: .atomic)
        } catch {
            AppLog.shared.error("Failed to save config: \(error)")
        }
    }
}
