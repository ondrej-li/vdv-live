import Foundation

/// Preferences the user can change on the settings screen.
struct AppSettings: Equatable, Sendable {
    /// Seconds between automatic refreshes.
    var autoRefreshInterval: TimeInterval
    /// Whether the map refreshes itself at all.
    var autoRefreshEnabled: Bool
    var language: AppLanguage
    /// Whether the map opens on the current location when it starts, unless a
    /// viewport has been locked.
    var startsAtCurrentLocation: Bool = true
    /// Viewport the user locked with the lock button, if any.
    ///
    /// It outranks the current location: locking one is a deliberate choice, and
    /// the location is only ever a guess.
    var savedMapView: SavedMapView?
    /// Distance within which buses are drawn as one marker.
    ///
    /// Zero, the default, leaves every vehicle on its own. Above that, vehicles
    /// within this distance of a group's anchor are drawn together.
    var clusterRadiusMetres: Double = 0
    /// Whether the map draws the user's own position as the usual blue dot.
    var showsCurrentLocation: Bool = true
    /// Whether the map keeps the position in the middle as it moves.
    var followsCurrentLocation: Bool = false

    /// The feed updates continuously, but not that fast: asking more often than
    /// every five seconds only costs battery.
    static let minimumAutoRefreshInterval: TimeInterval = 5
    static let defaultAutoRefreshInterval: TimeInterval = 15

    /// Intervals offered on the settings screen.
    static let selectableAutoRefreshIntervals: [TimeInterval] = [5, 10, 15, 30, 60, 120]

    /// Grouping radii offered on the settings screen. The first means "do not
    /// group anything", which is the default.
    static let selectableClusterRadii: [Double] = [0, 100, 250, 500, 1_000]

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
        settings.clusterRadiusMetres = clampedClusterRadius(settings.clusterRadiusMetres)
        return settings
    }

    /// A radius that is missing, negative or not a number means "do not group
    /// anything", which is the only safe reading of a value like that.
    static func clampedClusterRadius(_ radius: Double) -> Double {
        guard radius.isFinite, radius > 0 else { return 0 }
        return radius
    }
}
