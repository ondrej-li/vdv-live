import CoreLocation
import XCTest
@testable import VdvLive

final class MarkerMotionTests: XCTestCase {
    private let start = CLLocationCoordinate2D(latitude: 49.0, longitude: 15.0)
    private let end = CLLocationCoordinate2D(latitude: 49.4, longitude: 15.6)

    func testStartsAndEndsAtTheTwoPositions() {
        let from = MarkerMotion.position(from: start, to: end, progress: 0)
        let to = MarkerMotion.position(from: start, to: end, progress: 1)

        XCTAssertEqual(from.latitude, 49.0, accuracy: 0.000001)
        XCTAssertEqual(from.longitude, 15.0, accuracy: 0.000001)
        XCTAssertEqual(to.latitude, 49.4, accuracy: 0.000001)
        XCTAssertEqual(to.longitude, 15.6, accuracy: 0.000001)
    }

    func testHalfwayIsHalfway() {
        let middle = MarkerMotion.position(from: start, to: end, progress: 0.5)

        XCTAssertEqual(middle.latitude, 49.2, accuracy: 0.000001)
        XCTAssertEqual(middle.longitude, 15.3, accuracy: 0.000001)
    }

    /// A straight line at a constant speed: every quarter of the time covers a
    /// quarter of the distance.
    func testTheSpeedIsEven() {
        let steps = (0...4).map { step in
            MarkerMotion.position(from: start, to: end, progress: Double(step) / 4)
        }
        let hops = zip(steps, steps.dropFirst()).map { $1.latitude - $0.latitude }

        for hop in hops.dropFirst() {
            XCTAssertEqual(hop, hops[0], accuracy: 0.000001)
        }
        XCTAssertEqual(hops[0], 0.1, accuracy: 0.000001)
    }

    func testThePathIsAStraightLine() {
        // Three points on one line have equal slopes, which is what makes the
        // marker look like it is driving rather than drifting.
        let start = CLLocationCoordinate2D(latitude: 49.0, longitude: 15.0)
        let end = CLLocationCoordinate2D(latitude: 49.4, longitude: 15.8)

        func slope(from first: CLLocationCoordinate2D, to second: CLLocationCoordinate2D) -> Double {
            (second.latitude - first.latitude) / (second.longitude - first.longitude)
        }

        let points = (0...4).map {
            MarkerMotion.position(from: start, to: end, progress: Double($0) / 4)
        }
        let expected = slope(from: start, to: end)
        for (first, second) in zip(points, points.dropFirst()) {
            XCTAssertEqual(slope(from: first, to: second), expected, accuracy: 0.000001)
        }
    }

    func testPositionIsClampedToTheTwoEnds() {
        let before = MarkerMotion.position(from: start, to: end, progress: -1)
        let after = MarkerMotion.position(from: start, to: end, progress: 2)

        XCTAssertEqual(before.latitude, 49.0, accuracy: 0.000001)
        XCTAssertEqual(after.latitude, 49.4, accuracy: 0.000001)
    }

    func testAStandingVehicleIsNotWorthAnimating() {
        let here = CLLocationCoordinate2D(latitude: 49.4, longitude: 15.6)

        XCTAssertFalse(MarkerMotion.hasMoved(from: here, to: here))
        XCTAssertFalse(
            MarkerMotion.hasMoved(
                from: here,
                to: CLLocationCoordinate2D(latitude: 49.4 + 0.0000005, longitude: 15.6)
            )
        )
        XCTAssertTrue(
            MarkerMotion.hasMoved(
                from: here,
                to: CLLocationCoordinate2D(latitude: 49.4005, longitude: 15.6)
            )
        )
    }
}
