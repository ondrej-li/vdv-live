import Foundation

/// Preferences the user can change on the settings screen.
struct AppSettings: Equatable, Sendable {
    /// Seconds between automatic refreshes.
    var autoRefreshInterval: TimeInterval
    /// Whether the map refreshes itself at all.
    var autoRefreshEnabled: Bool
    var language: AppLanguage

    /// The feed updates continuously, but not that fast: asking more often than
    /// every five seconds only costs battery.
    static let minimumAutoRefreshInterval: TimeInterval = 5
    static let defaultAutoRefreshInterval: TimeInterval = 15

    /// Intervals offered on the settings screen.
    static let selectableAutoRefreshIntervals: [TimeInterval] = [5, 10, 15, 30, 60, 120]

    static let `default` = AppSettings(
        autoRefreshInterval: defaultAutoRefreshInterval,
        autoRefreshEnabled: true,
        language: .czech
    )

    /// Closest interval the app is willing to use.
    static func clampedAutoRefreshInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return defaultAutoRefreshInterval }
        return max(minimumAutoRefreshInterval, interval)
    }

    /// Interval with the minimum applied, for a value that came from outside.
    static func validated(_ settings: AppSettings) -> AppSettings {
        var settings = settings
        settings.autoRefreshInterval = clampedAutoRefreshInterval(settings.autoRefreshInterval)
        return settings
    }
}
