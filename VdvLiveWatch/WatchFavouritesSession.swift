import Foundation
import WatchConnectivity

/// Keeps the lines pinned on the phone, by listening for them.
///
/// The watch cannot read the phone's user defaults, so the phone sends the list on
/// both WatchConnectivity channels and this takes whichever arrives. The application
/// context is the state: it survives the watch app not running and is handed over
/// again the next time it launches, which is why activation reads it. A user info
/// transfer is the guaranteed one, queued if the watch was unreachable when the list
/// changed - including one queued before the watch app existed.
///
/// Only the lines travel. Vehicles are fetched by the watch itself, so the phone
/// does not have to be awake for the map to be current, and nothing here has to
/// wait on a reply.
@MainActor
final class WatchFavouritesSession: NSObject, WCSessionDelegate {
    /// Called when the stored list has changed, so the map can reload.
    var onChange: (() -> Void)?

    private nonisolated let store: FavouriteLinesPersisting

    /// Nil where WatchConnectivity cannot be used at all, which includes a watch
    /// simulator with no paired phone. Read rather than stored, because
    /// `WCSession` is not safe to hand around outside the main actor.
    private var session: WCSession? { WCSession.isSupported() ? .default : nil }

    nonisolated init(store: FavouriteLinesPersisting = UserDefaultsFavouriteLinesStore()) {
        self.store = store
        super.init()
    }

    /// Starts listening. Safe to call more than once.
    func activate() {
        guard let session else { return }
        // Assigning the delegate on an activated session is what re-delivers the
        // application context, so this also covers a launch after the phone has
        // already sent one.
        session.delegate = self
        session.activate()
    }

    /// Whatever the phone last sent, as far as the watch knows.
    var favouriteLines: FavouriteLines { store.load() }

    private func absorb(_ context: [String: Any]) {
        guard let lines = context[WatchFavouritesContext.key] as? [String] else { return }
        let received = FavouriteLines(lines)
        guard received != store.load() else { return }
        store.save(received)
        onChange?()
    }

    private func absorbCurrentContext(_ session: WCSession) {
        // Delivered contexts are advisory; on a fresh launch the map still has to
        // learn what the phone sent last time.
        let applicationContext = session.receivedApplicationContext
        if !applicationContext.isEmpty {
            absorb(applicationContext)
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            guard activationState == .activated else { return }
            absorbCurrentContext(session)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            absorb(applicationContext)
        }
    }

    /// The same list, over the channel that queues what the watch could not be told
    /// while it was unreachable. Absorbing it is idempotent, so a list that already
    /// arrived as a context changes nothing here.
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        Task { @MainActor in
            absorb(userInfo)
        }
    }
}
