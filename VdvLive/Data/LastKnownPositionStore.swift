import CoreLocation
import Foundation

/// Where the wearer was when the app last had a fix.
///
/// The watch opens its map on the wearer, and a fix is not something that can be
/// waited for: it takes a moment, and indoors or with location services switched off
/// it may never arrive at all. What was known last time is the answer to "where are
/// they" until the system says something better.
///
/// Only the watch uses this. The phone keeps the camera where the user left it,
/// which is a different question with a different answer.
///
/// `@unchecked Sendable` because `UserDefaults` is not marked `Sendable` in the SDK
/// even though it is safe to use from several threads.
struct LastKnownPositionStore: @unchecked Sendable {
    /// The key the position is kept under.
    static let defaultKey = "lastKnownPosition"
    /// The keys inside it, written out rather than abbreviated, so that the stored
    /// dictionary can be read by a person looking at it.
    static let latitudeKey = "latitude"
    static let longitudeKey = "longitude"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = LastKnownPositionStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    /// The last position seen, or `nil` when there has never been one.
    func load() -> CLLocationCoordinate2D? {
        guard let stored = defaults.dictionary(forKey: key),
              let latitude = stored[Self.latitudeKey] as? Double,
              let longitude = stored[Self.longitudeKey] as? Double else {
            return nil
        }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        // Anything the system would not accept as a position is not one, so a stored
        // value that cannot be placed counts as no stored value.
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return coordinate
    }

    func save(_ coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        defaults.set(
            [Self.latitudeKey: coordinate.latitude, Self.longitudeKey: coordinate.longitude],
            forKey: key
        )
    }
}
