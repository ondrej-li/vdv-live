import Foundation

/// Where the pinned lines are kept between launches.
protocol FavouriteLinesPersisting: Sendable {
    func load() -> FavouriteLines
    func save(_ lines: FavouriteLines)

    /// Whether the map shows only pinned lines.
    ///
    /// Remembered so that a user who wants a quiet map - one line among a few
    /// hundred - keeps it quiet on the next launch instead of having to filter
    /// again every time.
    func loadShowsOnlyFavourites() -> Bool
    func saveShowsOnlyFavourites(_ showsOnlyFavourites: Bool)
}

/// Keeps pinned lines in `UserDefaults`.
///
/// `@unchecked Sendable` because `UserDefaults` is not marked `Sendable` in the
/// SDK even though it is safe to use from several threads.
struct UserDefaultsFavouriteLinesStore: FavouriteLinesPersisting, @unchecked Sendable {
    static let defaultKey = "favouriteLines"
    static let showsOnlyFavouritesKey = "showsOnlyFavouriteLines"

    private let defaults: UserDefaults
    private let key: String
    private let showsOnlyFavouritesKey: String

    init(
        defaults: UserDefaults = .standard,
        key: String = UserDefaultsFavouriteLinesStore.defaultKey,
        showsOnlyFavouritesKey: String = UserDefaultsFavouriteLinesStore.showsOnlyFavouritesKey
    ) {
        self.defaults = defaults
        self.key = key
        self.showsOnlyFavouritesKey = showsOnlyFavouritesKey
    }

    func load() -> FavouriteLines {
        FavouriteLines(defaults.stringArray(forKey: key) ?? [])
    }

    func save(_ lines: FavouriteLines) {
        // Stored in display order so the plist stays readable and diffable.
        defaults.set(lines.orderedForDisplay, forKey: key)
    }

    func loadShowsOnlyFavourites() -> Bool {
        defaults.bool(forKey: showsOnlyFavouritesKey)
    }

    func saveShowsOnlyFavourites(_ showsOnlyFavourites: Bool) {
        defaults.set(showsOnlyFavourites, forKey: showsOnlyFavouritesKey)
    }
}

/// Store that only lives for as long as the process does.
///
/// Used by previews and by tests, which must not touch the real user defaults.
final class InMemoryFavouriteLinesStore: FavouriteLinesPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var lines: FavouriteLines
    private var showsOnlyFavourites: Bool
    private(set) var saveCount = 0

    init(lines: FavouriteLines = FavouriteLines(), showsOnlyFavourites: Bool = false) {
        self.lines = lines
        self.showsOnlyFavourites = showsOnlyFavourites
    }

    func load() -> FavouriteLines {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    func save(_ lines: FavouriteLines) {
        lock.lock()
        defer { lock.unlock() }
        self.lines = lines
        saveCount += 1
    }

    func loadShowsOnlyFavourites() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return showsOnlyFavourites
    }

    func saveShowsOnlyFavourites(_ showsOnlyFavourites: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.showsOnlyFavourites = showsOnlyFavourites
    }
}
