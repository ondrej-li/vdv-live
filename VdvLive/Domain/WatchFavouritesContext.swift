import Foundation

/// The one thing the phone and the watch have to agree on: what the phone calls the
/// list of pinned lines when it hands it over.
///
/// Lives in the shared domain so neither side can drift from the other, and so the
/// key is in one place when a second piece of state ever needs to travel.
enum WatchFavouritesContext {
    /// The key the phone writes the pinned lines under in the session context.
    static let key = "favouriteLines"

    /// What the phone should put on each of WatchConnectivity's two channels, given
    /// the lines it has now and the ones it last queued.
    ///
    /// Two answers rather than one, because the channels do different jobs:
    ///
    /// - the application context holds the *state*, and is rewritten on every write
    ///   of any default at all, so that a watch out of range for a week ends up with
    ///   the list as it is now rather than as it was when it left;
    /// - a user info transfer is the *guaranteed* channel - queued, delivered in
    ///   order, and continued while the sending app is suspended - and carries the
    ///   list only when the list itself changed. Queuing one per settings write
    ///   would pile up transfers saying the same thing, and only the newest member
    ///   of that pile is worth anything.
    static func announcement(
        for lines: FavouriteLines,
        lastQueued: [String]?
    ) -> (context: [String], queued: [String]?) {
        let ordered = lines.orderedForDisplay
        guard ordered != lastQueued else { return (ordered, nil) }
        return (ordered, ordered)
    }
}
