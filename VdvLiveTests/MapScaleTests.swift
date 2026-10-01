import CoreGraphics
import XCTest
@testable import VdvLive

final class MapScaleTests: XCTestCase {
    func testNeedsASpanAndAMapSize() {
        XCTAssertNil(MapScale.make(latitudeSpan: 0, mapHeight: 800))
        XCTAssertNil(MapScale.make(latitudeSpan: -1, mapHeight: 800))
        XCTAssertNil(MapScale.make(latitudeSpan: 0.5, mapHeight: 0))
        XCTAssertNil(MapScale.make(latitudeSpan: 0.5, mapHeight: 800, targetLength: 0))
    }

    func testPicksARoundDistanceForTheZoomLevel() throws {
        // 0.5° of latitude over 800 points is about 69.5 m per point, so an 88
        // point bar would be a little over 6 km: 5 km is the round number below.
        let scale = try XCTUnwrap(MapScale.make(latitudeSpan: 0.5, mapHeight: 800))

        XCTAssertEqual(scale.distanceMetres, 5_000)
        XCTAssertEqual(scale.labelText, "5 km")
        XCTAssertEqual(Double(scale.barLength), 5_000 / 69.4575, accuracy: 0.001)
    }

    func testBarStaysCloseToTheRequestedLength() throws {
        for span in [0.01, 0.05, 0.2, 0.5, 1.0, 3.0] {
            let scale = try XCTUnwrap(
                MapScale.make(latitudeSpan: span, mapHeight: 800),
                "No scale for span \(span)"
            )
            XCTAssertGreaterThan(scale.barLength, 40, "span \(span)")
            XCTAssertLessThan(scale.barLength, 130, "span \(span)")
        }
    }

    func testZoomingOutPicksALongerDistance() throws {
        let close = try XCTUnwrap(MapScale.make(latitudeSpan: 0.1, mapHeight: 800))
        let far = try XCTUnwrap(MapScale.make(latitudeSpan: 2.0, mapHeight: 800))

        XCTAssertEqual(close.distanceMetres, 1_000)
        XCTAssertEqual(far.distanceMetres, 20_000)
        XCTAssertLessThan(close.distanceMetres, far.distanceMetres)
    }

    func testFallsBackToTheLongestStepWhenEvenThatBarIsTooLong() throws {
        // Zoomed right out, every step is shorter than the target: the legend
        // still has to say something rather than disappear.
        let scale = try XCTUnwrap(MapScale.make(latitudeSpan: 40, mapHeight: 400))

        XCTAssertEqual(scale.distanceMetres, MapScale.stepDistances.last)
    }

    func testLabelsSwitchFromMetresToKilometres() {
        XCTAssertEqual(MapScale(distanceMetres: 100, barLength: 60).labelText, "100 m")
        XCTAssertEqual(MapScale(distanceMetres: 500, barLength: 60).labelText, "500 m")
        XCTAssertEqual(MapScale(distanceMetres: 1_000, barLength: 60).labelText, "1 km")
        XCTAssertEqual(MapScale(distanceMetres: 200_000, barLength: 60).labelText, "200 km")
    }
}
