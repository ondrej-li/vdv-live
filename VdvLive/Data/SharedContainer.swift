import Foundation
import WidgetKit

/// The storage the app shares with its widgets.
///
/// A widget runs in its own process and its own container, so nothing the app keeps
/// in `UserDefaults.standard` or in its caches directory is visible to it. What the
/// two need to agree on - the pinned lines, the starred stops, the position and the
/// timetables a board is built from - lives in an app group instead.
///
/// Every accessor falls back to the app's own storage when the group is not there,
/// which is the case on the watch and in tests that run without entitlements. That
/// keeps one code path: the app writes to whichever container it has, and a widget
/// reads the shared one.
enum SharedContainer {
    /// Identifiers of the group, matching the app group registered for both bundles.
    static let appGroupIdentifier = "group.cz.ondralinek.VdvLive"

    /// Keys both the app and the widgets read.
    enum Key {
        static let favouriteLines = UserDefaultsFavouriteLinesStore.defaultKey
        static let showsOnlyFavouriteLines = UserDefaultsFavouriteLinesStore.showsOnlyFavouritesKey
        static let starredStops = UserDefaultsStarredStopsStore.defaultKey
        static let lastKnownPosition = LastKnownPositionStore.defaultKey

        /// Everything a fresh install has to carry over from `UserDefaults.standard`,
        /// which is where these lived before the widgets needed to read them.
        static let all = [
            favouriteLines, showsOnlyFavouriteLines, starredStops, lastKnownPosition
        ]
    }

    /// The group's container, or `nil` when the bundle has no such entitlement.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// Defaults the app and the widgets both read.
    ///
    /// `UserDefaults(suiteName:)` hands back a store even without the entitlement,
    /// but that store is private to the process, so the group's container is what
    /// decides whether the suite is really shared.
    static var defaults: UserDefaults {
        guard containerURL != nil, let shared = UserDefaults(suiteName: appGroupIdentifier) else {
            return .standard
        }
        return shared
    }

    /// Where the timetable index and the line entries are kept, so that a widget
    /// builds a board from the same archive the app downloaded.
    static let timetableDirectory: URL = {
        let fallback = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        guard let container = containerURL else {
            return fallback.appendingPathComponent("timetables", isDirectory: true)
        }
        let directory = container
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent("timetables", isDirectory: true)
        moveTimetablesIfNeeded(from: fallback.appendingPathComponent("timetables", isDirectory: true),
                               to: directory)
        return directory
    }()

    /// Copies what the app stored before it had a group into the group, once.
    ///
    /// Not a move: the old values are left where they are, because a process that
    /// cannot see the group - the watch, a test host - still reads them. A key the
    /// group already has is never overwritten, so a second launch changes nothing.
    static func copyDefaultsFromAppIfNeeded(from app: UserDefaults = .standard,
                                            to shared: UserDefaults = defaults,
                                            keys: [String] = Key.all) {
        guard app !== shared else { return }
        for key in keys {
            guard shared.object(forKey: key) == nil,
                  let value = app.object(forKey: key) else { continue }
            shared.set(value, forKey: key)
        }
    }

    /// Tells the widgets that something they read has changed.
    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Moves a cache written before the group existed, so that a board does not have
    /// to download the archive index again after the update.
    private static func moveTimetablesIfNeeded(from old: URL, to new: URL) {
        let manager = FileManager.default
        guard !old.standardizedFileURL.path.isEmpty,
              old.standardizedFileURL != new.standardizedFileURL else { return }
        guard !manager.fileExists(atPath: new.appendingPathComponent("index.json").path),
              manager.fileExists(atPath: old.appendingPathComponent("index.json").path) else { return }
        try? manager.createDirectory(at: new, withIntermediateDirectories: true)
        for name in (try? manager.contentsOfDirectory(atPath: old.path)) ?? [] {
            try? manager.moveItem(at: old.appendingPathComponent(name),
                                  to: new.appendingPathComponent(name))
        }
    }
}
