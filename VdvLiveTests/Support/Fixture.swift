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

    /// Vehicles on a square grid: `count` of them to a side, `spacing` degrees
    /// apart, running north east from the given corner. The number the whole thing
    /// is built to be is `count * count`.
    static func grid(
        count: Int,
        spacing: Double,
        latitude: Double = 49.0,
        longitude: Double = 15.2
    ) -> [Vehicle] {
        var vehicles: [Vehicle] = []
        for row in 0..<count {
            for column in 0..<count {
                vehicles.append(vehicle(
                    id: vehicles.count + 1,
                    latitude: latitude + Double(row) * spacing,
                    longitude: longitude + Double(column) * spacing
                ))
            }
        }
        return vehicles
    }
}
