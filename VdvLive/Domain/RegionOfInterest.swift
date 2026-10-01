import CoreLocation
import MapKit

/// The part of the world this app is built around.
///
/// The Vysočina Region (Kraj Vysočina) is one of the fourteen regions of
/// Czechia. The feed behind `mapavdv.kr-vysocina.cz` covers it, with a few
/// vehicles reporting positions outside the region while they run long
/// distance services.
enum RegionOfInterest {
    /// Roughly the boundary of the Vysočina Region.
    static let vysocina = BoundingBox(
        southLatitude: 48.85,
        westLongitude: 14.70,
        northLatitude: 49.95,
        eastLongitude: 16.65
    )

    /// Span used when the map zooms in on a single vehicle.
    static let vehicleFocusSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)

    /// An axis aligned latitude/longitude rectangle.
    struct BoundingBox: Hashable, Sendable {
        let southLatitude: Double
        let westLongitude: Double
        let northLatitude: Double
        let eastLongitude: Double

        var latitudeSpan: Double { northLatitude - southLatitude }
        var longitudeSpan: Double { eastLongitude - westLongitude }

        init(
            southLatitude: Double,
            westLongitude: Double,
            northLatitude: Double,
            eastLongitude: Double
        ) {
            self.southLatitude = southLatitude
            self.westLongitude = westLongitude
            self.northLatitude = northLatitude
            self.eastLongitude = eastLongitude
        }

        /// Box covering exactly what a map region shows.
        init(region: MKCoordinateRegion) {
            let latitudeRadius = region.span.latitudeDelta / 2
            let longitudeRadius = region.span.longitudeDelta / 2
            self.init(
                southLatitude: region.center.latitude - latitudeRadius,
                westLongitude: region.center.longitude - longitudeRadius,
                northLatitude: region.center.latitude + latitudeRadius,
                eastLongitude: region.center.longitude + longitudeRadius
            )
        }

        var center: CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: (southLatitude + northLatitude) / 2,
                longitude: (westLongitude + eastLongitude) / 2
            )
        }

        /// Map region covering the box, with a little breathing room so that
        /// markers on the border are not cut off.
        var region: MKCoordinateRegion {
            let padding = 1.12
            return MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(
                    latitudeDelta: latitudeSpan * padding,
                    longitudeDelta: longitudeSpan * padding
                )
            )
        }

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            (southLatitude...northLatitude).contains(coordinate.latitude)
                && (westLongitude...eastLongitude).contains(coordinate.longitude)
        }
    }
}
