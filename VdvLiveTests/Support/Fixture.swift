import CoreLocation
import MapKit
@testable import VdvLive

/// Builders shared by the test cases.
enum Fixture {
    static func vehicle(
        id: Int,
        line: String = "841334",
        latitude: Double = 49.3960,
        longitude: Double = 15.5910,
        destination: String? = "Jihlava,aut.nádr.",
        delay: VehicleDelay = .minutes(0),
        traction: Traction = .bus
    ) -> Vehicle {
        Vehicle(
            id: id,
            line: line,
            latitude: latitude,
            longitude: longitude,
            destination: destination,
            delay: delay,
            traction: traction
        )
    }

    /// Region used by the grid tests: 1 degree wide and tall, centred on the
    /// middle of the Vysočina Region.
    static let squareRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.4, longitude: 15.6),
        span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
    )
}
