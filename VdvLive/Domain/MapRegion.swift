import CoreLocation
import MapKit

/// A viewport described the way a person thinks about it: a centre and a size in
/// metres, rather than two spans in degrees.
///
/// A degree of latitude is very nearly the same distance everywhere, but a
/// degree of longitude shrinks towards the poles, so the same square needs
/// different numbers for its two spans.
enum MapRegion {
    /// Width and height of the neighbourhood the map opens on when it starts at
    /// the current location.
    static let currentLocationMetres: Double = 10_000

    /// Width and height of the window a map shows when it is told to show the user:
    /// five kilometres, close enough to read the streets and far enough to hold the
    /// buses about to pass. A double tap asks for this on the phone and on the
    /// watch, so both ask for the same window.
    static let focusMetres: Double = 5_000

    /// Region showing `widthMetres` by `heightMetres` around `center`.
    static func region(
        around center: CLLocationCoordinate2D,
        widthMetres: Double,
        heightMetres: Double
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: heightMetres / MapScale.metresPerDegreeLatitude,
                longitudeDelta: widthMetres / metresPerDegreeLongitude(at: center.latitude)
            )
        )
    }

    /// Ground distance one degree of longitude covers at `latitude`.
    ///
    /// The result is kept away from zero so that a coordinate near a pole cannot
    /// turn the span into infinity.
    static func metresPerDegreeLongitude(at latitude: Double) -> Double {
        let shrink = max(cos(latitude * .pi / 180), 0.01)
        return MapScale.metresPerDegreeLatitude * shrink
    }
}
