import CoreLocation
@testable import VdvLive

/// Location stand-in: hands out a fixed position, or nothing at all, and counts
/// how often it was asked.
///
/// CoreLocation cannot be driven from a unit test, which is the whole reason the
/// map asks through a protocol.
@MainActor
final class StubLocationProvider: LocationProviding {
    var coordinate: CLLocationCoordinate2D?
    /// What ``requestAuthorization()`` answers.
    var isAuthorized = true
    private(set) var requestCount = 0
    private(set) var authorizationRequestCount = 0

    init(coordinate: CLLocationCoordinate2D? = nil, isAuthorized: Bool = true) {
        self.coordinate = coordinate
        self.isAuthorized = isAuthorized
    }

    func requestCurrentCoordinate() async -> CLLocationCoordinate2D? {
        requestCount += 1
        return coordinate
    }

    func requestAuthorization() async -> Bool {
        authorizationRequestCount += 1
        return isAuthorized
    }
}
