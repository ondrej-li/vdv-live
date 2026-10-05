import Foundation

/// The one thing the phone and the watch have to agree on: what the phone calls the
/// list of pinned lines when it hands it over.
///
/// Lives in the shared domain so neither side can drift from the other, and so the
/// key is in one place when a second piece of state ever needs to travel.
enum WatchFavouritesContext {
    /// The key the phone writes the pinned lines under in the session context.
    static let key = "favouriteLines"
}
