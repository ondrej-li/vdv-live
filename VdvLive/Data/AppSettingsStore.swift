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
    static let startsAtCurrentLocationKey = "startsAtCurrentLocation"
    static let savedMapViewKey = "savedMapView"
    static let clusterRadiusMetresKey = "clusterRadiusMetres"
    static let showsCurrentLocationKey = "showsCurrentLocation"

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
                language: storedLanguage ?? AppSettings.default.language,
                startsAtCurrentLocation: defaults.object(forKey: Self.startsAtCurrentLocationKey) as? Bool
                    ?? AppSettings.default.startsAtCurrentLocation,
                savedMapView: Self.savedMapView(from: defaults),
                clusterRadiusMetres: defaults.object(forKey: Self.clusterRadiusMetresKey) as? Double
                    ?? AppSettings.default.clusterRadiusMetres,
                showsCurrentLocation: defaults.object(forKey: Self.showsCurrentLocationKey) as? Bool
                    ?? AppSettings.default.showsCurrentLocation
            )
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(settings.autoRefreshInterval, forKey: Self.autoRefreshIntervalKey)
        defaults.set(settings.autoRefreshEnabled, forKey: Self.autoRefreshEnabledKey)
        defaults.set(settings.language.rawValue, forKey: Self.languageKey)
        defaults.set(settings.startsAtCurrentLocation, forKey: Self.startsAtCurrentLocationKey)
        defaults.set(settings.clusterRadiusMetres, forKey: Self.clusterRadiusMetresKey)
        defaults.set(settings.showsCurrentLocation, forKey: Self.showsCurrentLocationKey)
        if let savedMapView = settings.savedMapView {
            defaults.set(savedMapView.storedValues, forKey: Self.savedMapViewKey)
        } else {
            // Removing rather than writing zeroes: an absent key is what "no
            // viewport has been locked" looks like on the way back in.
            defaults.removeObject(forKey: Self.savedMapViewKey)
        }
    }

    /// Rebuilds the locked viewport, ignoring a value that is incomplete or was
    /// written by something else entirely.
    private static func savedMapView(from defaults: UserDefaults) -> SavedMapView? {
        guard let stored = defaults.dictionary(forKey: savedMapViewKey) else { return nil }

        var values: [String: Double] = [:]
        for (key, value) in stored {
            guard let number = value as? NSNumber else { return nil }
            values[key] = number.doubleValue
        }
        return SavedMapView(storedValues: values)
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
