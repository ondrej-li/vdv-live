import Foundation

/// Where the starred stops are kept between launches.
protocol StarredStopsPersisting: Sendable {
    func load() -> StarredStops
    func save(_ stops: StarredStops)
}

/// Starred stops in `UserDefaults`, as the display names the user starred.
///
/// Names rather than positions: a stop starred before the table was rebuilt is still the
/// same stop afterwards, and a stop with no position can be starred from a search.
struct UserDefaultsStarredStopsStore: StarredStopsPersisting, @unchecked Sendable {
    static let defaultKey = "starredStops"

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, key: String = UserDefaultsStarredStopsStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> StarredStops {
        lock.lock()
        defer { lock.unlock() }
        return StarredStops(defaults.stringArray(forKey: key) ?? [])
    }

    func save(_ stops: StarredStops) {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(stops.names, forKey: key)
    }
}

/// Starred stops held in memory, for tests and for the previews.
final class InMemoryStarredStopsStore: StarredStopsPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var stops: StarredStops
    private(set) var saveCount = 0

    init(stops: StarredStops = StarredStops()) {
        self.stops = stops
    }

    func load() -> StarredStops {
        lock.lock()
        defer { lock.unlock() }
        return stops
    }

    func save(_ stops: StarredStops) {
        lock.lock()
        defer { lock.unlock() }
        self.stops = stops
        saveCount += 1
    }
}
