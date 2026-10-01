import CoreLocation
import MapKit

/// The viewport the user locked with the lock button: where the map should open
/// next time, and how far in it was zoomed.
///
/// Stored as four plain numbers rather than a `Data` blob, so that the value in
/// the user defaults stays readable and a partially written value can be
/// recognised instead of decoded into nonsense.
struct SavedMapView: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var latitudeDelta: Double
    var longitudeDelta: Double

    /// Keys the viewport is written under in the user defaults.
    enum Key {
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let latitudeDelta = "latitudeDelta"
        static let longitudeDelta = "longitudeDelta"
    }

    /// Fails for a region that cannot be restored later: a span of nothing, a
    /// span that is not a number, or a coordinate off the planet.
    init?(region: MKCoordinateRegion) {
        guard CLLocationCoordinate2DIsValid(region.center),
              region.span.latitudeDelta.isFinite, region.span.longitudeDelta.isFinite,
              region.span.latitudeDelta > 0, region.span.longitudeDelta > 0
        else { return nil }

        latitude = region.center.latitude
        longitude = region.center.longitude
        latitudeDelta = region.span.latitudeDelta
        longitudeDelta = region.span.longitudeDelta
    }

    /// Reads a viewport out of the user defaults, ignoring anything that is not
    /// a complete, usable rectangle.
    init?(storedValues: [String: Double]) {
        guard let latitude = storedValues[Key.latitude],
              let longitude = storedValues[Key.longitude],
              let latitudeDelta = storedValues[Key.latitudeDelta],
              let longitudeDelta = storedValues[Key.longitudeDelta]
        else { return nil }

        self.init(
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(
                    latitudeDelta: latitudeDelta,
                    longitudeDelta: longitudeDelta
                )
            )
        )
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    /// Shape the viewport takes in the user defaults.
    var storedValues: [String: Double] {
        [
            Key.latitude: latitude,
            Key.longitude: longitude,
            Key.latitudeDelta: latitudeDelta,
            Key.longitudeDelta: longitudeDelta
        ]
    }
}
