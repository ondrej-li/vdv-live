import CoreLocation
import XCTest
@testable import VdvLive

/// What the starred traffic widget counts as "around me": the pinned lines, nothing
/// else, nearest first, and never a guess about where the reader is.
final class NearbyVehiclesTests: XCTestCase {
    private let telc = CLLocationCoordinate2D(latitude: 49.1842, longitude: 15.4528)

    /// A vehicle a given distance east of Telč, roughly: 0.01° of longitude is 700 m
    /// at this latitude, which is close enough for a ranking test.
    private func vehicle(id: Int,
                         line: String,
                         metresEast: Double,
                         delay: Int? = 0) -> Vehicle {
        Vehicle(
            id: id,
            line: line,
            latitude: telc.latitude,
            longitude: telc.longitude + metresEast / 700 * 0.01,
            destination: "Jihlava",
            delay: delay.map(VehicleDelay.init(rawMinutes:)) ?? .unknown,
            traction: .bus
        )
    }

    func testKeepsOnlyPinnedLines() {
        let vehicles = [
            vehicle(id: 1, line: "764420", metresEast: 500),
            vehicle(id: 2, line: "764337", metresEast: 100),
            vehicle(id: 3, line: "764999", metresEast: 50)
        ]

        let nearby = NearbyVehicles.nearby(in: vehicles,
                                           pinnedTo: FavouriteLines(["420"]),
                                           from: telc)

        XCTAssertEqual(nearby.map(\.vehicle.id), [1])
    }

    func testOrdersByDistanceFromTheReader() {
        let vehicles = [
            vehicle(id: 1, line: "764420", metresEast: 4_000),
            vehicle(id: 2, line: "764337", metresEast: 800),
            vehicle(id: 3, line: "764420", metresEast: 2_000)
        ]

        let nearby = NearbyVehicles.nearby(in: vehicles,
                                           pinnedTo: FavouriteLines(["420", "337"]),
                                           from: telc)

        XCTAssertEqual(nearby.map(\.vehicle.id), [2, 3, 1])
    }

    func testDropsVehiclesBeyondTheRadius() {
        let vehicles = [
            vehicle(id: 1, line: "764420", metresEast: 200),
            vehicle(id: 2, line: "764420", metresEast: 40_000)
        ]

        let nearby = NearbyVehicles.nearby(in: vehicles,
                                           pinnedTo: FavouriteLines(["420"]),
                                           from: telc)

        XCTAssertEqual(nearby.map(\.vehicle.id), [1])
    }

    func testWithoutAPositionThereIsNoAround() {
        let vehicles = [vehicle(id: 1, line: "764420", metresEast: 200)]

        XCTAssertTrue(NearbyVehicles.nearby(in: vehicles,
                                            pinnedTo: FavouriteLines(["420"]),
                                            from: nil).isEmpty)
    }

    func testWithoutPinnedLinesThereIsNothingOfTheReadersOwn() {
        let vehicles = [vehicle(id: 1, line: "764420", metresEast: 200)]

        XCTAssertTrue(NearbyVehicles.nearby(in: vehicles,
                                            pinnedTo: FavouriteLines(),
                                            from: telc).isEmpty)
    }

    func testLimitsHowManyFit() {
        let vehicles = (1...6).map {
            vehicle(id: $0, line: "764420", metresEast: Double($0) * 100)
        }

        let nearby = NearbyVehicles.nearby(in: vehicles,
                                           pinnedTo: FavouriteLines(["420"]),
                                           from: telc,
                                           limit: 2)

        XCTAssertEqual(nearby.count, 2)
    }

    func testAVehicleTheFeedCannotPlaceIsNotNearAnything() {
        let unplaced = Vehicle(id: 9,
                               line: "764420",
                               latitude: 0,
                               longitude: 0,
                               destination: nil,
                               delay: .unknown,
                               traction: .bus)

        XCTAssertTrue(NearbyVehicles.nearby(in: [unplaced],
                                            pinnedTo: FavouriteLines(["420"]),
                                            from: telc).isEmpty)
    }

    func testTheWidgetExplainsWhatItIsMissing() {
        XCTAssertEqual(WidgetContent.traffic(vehicles: [], pinnedTo: FavouriteLines(), from: telc),
                       .needsPinnedLines)
        XCTAssertEqual(WidgetContent.traffic(vehicles: [],
                                             pinnedTo: FavouriteLines(["420"]),
                                             from: nil),
                       .needsPosition)
    }
}
