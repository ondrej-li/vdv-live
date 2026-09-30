import Foundation

/// Where the settings screen's choices are kept.
protocol AppSettingsStoring: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

/// Keeps the settings in `UserDefaults`.
///
/// `@unchecked Sendable` because `UserDefaults` is not marked `Sendable` in the
/// SDK even though it is safe to use from several threads.
struct UserDefaultsAppSettingsStore: AppSettingsStoring, @unchecked Sendable {
    static let autoRefreshIntervalKey = "autoRefreshInterval"
    static let autoRefreshEnabledKey = "autoRefreshEnabled"
    static let languageKey = "appLanguage"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        let storedInterval = defaults.object(forKey: Self.autoRefreshIntervalKey) as? Double
        let storedLanguage = defaults
            .string(forKey: Self.languageKey)
            .flatMap(AppLanguage.init(rawValue:))

        return AppSettings.validated(
            AppSettings(
                autoRefreshInterval: storedInterval ?? AppSettings.defaultAutoRefreshInterval,
                autoRefreshEnabled: defaults.object(forKey: Self.autoRefreshEnabledKey) as? Bool
                    ?? AppSettings.default.autoRefreshEnabled,
                language: storedLanguage ?? AppSettings.default.language
            )
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(settings.autoRefreshInterval, forKey: Self.autoRefreshIntervalKey)
        defaults.set(settings.autoRefreshEnabled, forKey: Self.autoRefreshEnabledKey)
        defaults.set(settings.language.rawValue, forKey: Self.languageKey)
    }
}

/// Store that only lives for as long as the process does.
///
/// Used by previews and by tests, which must not touch the real user defaults.
final class InMemoryAppSettingsStore: AppSettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AppSettings
    private(set) var saveCount = 0

    init(settings: AppSettings = .default) {
        self.settings = settings
    }

    func load() -> AppSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    func save(_ settings: AppSettings) {
        lock.lock()
        defer { lock.unlock() }
        self.settings = settings
        saveCount += 1
    }
}
