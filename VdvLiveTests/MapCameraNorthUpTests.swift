import MapKit
import SwiftUI
import XCTest
@testable import VdvLive

/// The north-up reset works on a camera rather than a region, and this is the
/// part of it that can be checked without a map on screen.
final class MapCameraNorthUpTests: XCTestCase {
    func testTakesTheDirectionOutAndKeepsThePlace() {
        let turned = MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 49.4, longitude: 15.6),
            distance: 12_000,
            heading: 37,
            pitch: 22
        )

        let north = turned.pointingNorth

        XCTAssertEqual(north.heading, 0)
        XCTAssertEqual(north.pitch, 0)
        XCTAssertEqual(north.centerCoordinate.latitude, 49.4, accuracy: 0.0001)
        XCTAssertEqual(north.centerCoordinate.longitude, 15.6, accuracy: 0.0001)
        XCTAssertEqual(north.distance, 12_000, accuracy: 1)
    }

    func testLeavesANorthUpCameraWhereItIs() {
        let alreadyNorth = MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 49.2, longitude: 16.1),
            distance: 40_000,
            heading: 0,
            pitch: 0
        )

        let north = alreadyNorth.pointingNorth

        XCTAssertEqual(north.heading, 0)
        XCTAssertEqual(north.pitch, 0)
        XCTAssertEqual(north.distance, 40_000, accuracy: 1)
    }

    /// A tilt without a turn is still a direction to be taken out.
    func testFlattensATiltedMap() {
        let tilted = MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 49.4, longitude: 15.6),
            distance: 8_000,
            heading: 0,
            pitch: 45
        )

        XCTAssertEqual(tilted.pointingNorth.pitch, 0)
    }
}
