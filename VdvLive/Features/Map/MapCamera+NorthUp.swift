import MapKit
import SwiftUI

extension MapCamera {
    /// The same camera, pointing north with no tilt.
    ///
    /// A region cannot express this. `MapCameraPosition.region` says *what* to
    /// look at, not which way is up, so handing one to a map the user has turned
    /// leaves the map turned - which is why a reset built on a region appears to
    /// do nothing at all. A camera carries the heading and the pitch itself, so
    /// this is the only way to say "here, but north".
    var pointingNorth: MapCamera {
        MapCamera(
            centerCoordinate: centerCoordinate,
            distance: distance,
            heading: 0,
            pitch: 0
        )
    }
}
