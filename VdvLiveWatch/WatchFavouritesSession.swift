import Foundation
import WatchConnectivity

/// Keeps the lines pinned on the phone, by listening for them.
///
/// The watch cannot read the phone's user defaults, so the phone sends the list as
/// the session's application context. That suits a short list of line numbers: an
/// application context survives the watch app not running and is handed over again
/// the next time it launches.
///
/// Only the lines travel. Vehicles are fetched by the watch itself, so the phone
/// does not have to be awake for the map to be current, and nothing here has to
/// wait on a reply.
@MainActor
final class WatchFavouritesSession: NSObject, WCSessionDelegate {
    /// Called when the stored list has changed, so the map can reload.
    var onChange: (() -> Void)?

    private let store: FavouriteLinesPersisting
    private let session: WCSession?

    nonisolated init(store: FavouriteLinesPersisting = UserDefaultsFavouriteLinesStore()) {
        self.store = store
        self.session = WCSession.isSupported() ? .default : nil
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
}
