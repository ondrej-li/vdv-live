import Foundation
import WatchConnectivity

/// Hands the phone's pinned lines to the watch.
///
/// Lines only, never vehicles: the watch fetches the feed itself, so the phone does
/// not have to be awake and the payload stays small enough to send on every change.
/// Publishing is driven by the user defaults notification rather than by the map
/// screen, so pinning a line anywhere in the app reaches the watch.
///
/// The same list goes out on both of WatchConnectivity's channels, for different
/// reasons: the application context is the state and always reflects the list as it
/// is now, and a user info transfer is the channel that guarantees delivery, which
/// is what seeds a watch app that was installed after the list was last changed.
/// `WatchFavouritesContext.announcement(for:lastQueued:)` decides what each gets.
@MainActor
final class WatchFavouritesPublisher: NSObject, WCSessionDelegate {
    private let store: FavouriteLinesPersisting
    private let session: WCSession?
    private var observer: NSObjectProtocol?
    /// The list last handed to the queued channel, so that writing anything else to
    /// the defaults does not queue the same list again.
    private var lastQueuedLines: [String]?

    init(store: FavouriteLinesPersisting = UserDefaultsFavouriteLinesStore()) {
        self.store = store
        self.session = WCSession.isSupported() ? .default : nil
        super.init()
    }

    /// Starts watching for changes and sends the current list.
    func start() {
        guard let session else { return }
        session.delegate = self
        session.activate()
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        publish()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func publish() {
        guard let session, session.activationState == .activated else { return }
        // The watch may have been out of range for days; sending only on change
        // would leave it with a stale list, so the context is refreshed whenever
        // the phone writes anything to its defaults.
        let announcement = WatchFavouritesContext.announcement(
            for: store.load(),
            lastQueued: lastQueuedLines
        )
        try? session.updateApplicationContext([WatchFavouritesContext.key: announcement.context])
        guard let queued = announcement.queued else { return }
        session.transferUserInfo([WatchFavouritesContext.key: queued])
        lastQueuedLines = queued
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            guard activationState == .activated else { return }
            publish()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // A watch can be swapped for another one; activating again is what makes
        // the new one receive the context.
        session.activate()
    }
}
