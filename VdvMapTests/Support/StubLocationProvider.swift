import CoreLocation
@testable import VdvMap

/// Location stand-in: hands out a fixed position, or nothing at all, and counts
/// how often it was asked.
///
/// CoreLocation cannot be driven from a unit test, which is the whole reason the
/// map asks through a protocol.
@MainActor
final class StubLocationProvider: LocationProviding {
    var coordinate: CLLocationCoordinate2D?
    private(set) var requestCount = 0

    init(coordinate: CLLocationCoordinate2D? = nil) {
        self.coordinate = coordinate
    }

    func requestCurrentCoordinate() async -> CLLocationCoordinate2D? {
        requestCount += 1
        return coordinate
    }
}
