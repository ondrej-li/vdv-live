import CoreLocation
import XCTest
@testable import VdvLive

final class MapZoomTests: XCTestCase {
    func testTheEndsOfTheCrownAreTheLimits() {
        XCTAssertEqual(MapZoom.span(forCrownValue: 0).latitudeDelta,
                       MapZoom.closestLatitudeDelta, accuracy: 0.000001)
        XCTAssertEqual(MapZoom.span(forCrownValue: 1).latitudeDelta,
                       MapZoom.widestLatitudeDelta, accuracy: 0.000001)
    }

    /// Turning the crown one way always zooms in, never back out.
    func testTheSpanOnlyGrowsAsTheCrownTurns() {
        let spans = stride(from: 0.0, through: 1.0, by: 0.05)
            .map { MapZoom.span(forCrownValue: $0).latitudeDelta }

        XCTAssertEqual(spans, spans.sorted())
        XCTAssertEqual(Set(spans).count, spans.count)
    }

    /// The step is a fixed proportion, which is what makes the crown feel even.
    func testEachStepChangesTheScaleByTheSameProportion() {
        let ratios = stride(from: 0.0, through: 0.9, by: 0.1).map { value in
            MapZoom.span(forCrownValue: value + 0.1).latitudeDelta
                / MapZoom.span(forCrownValue: value).latitudeDelta
        }

        for ratio in ratios {
            XCTAssertEqual(ratio, ratios[0], accuracy: 0.000001)
        }
        XCTAssertGreaterThan(ratios[0], 1)
    }

    /// A crown value can arrive from the framework slightly out of range.
    func testValuesOutsideTheCrownRangeAreClamped() {
        XCTAssertEqual(MapZoom.span(forCrownValue: -2).latitudeDelta,
                       MapZoom.closestLatitudeDelta, accuracy: 0.000001)
        XCTAssertEqual(MapZoom.span(forCrownValue: 4).latitudeDelta,
                       MapZoom.widestLatitudeDelta, accuracy: 0.000001)
    }

    /// A window asked for by its size has to leave the crown where it left the map.
    func testCrownValueInvertsTheSpan() {
        for value in stride(from: 0.0, through: 1.0, by: 0.1) {
            let span = MapZoom.span(forCrownValue: value).latitudeDelta

            XCTAssertEqual(MapZoom.crownValue(forLatitudeDelta: span), value, accuracy: 0.000001)
        }
    }

    /// A window outside what the crown can show is answered with its end, so the
    /// next turn of the crown still goes the way it should.
    func testCrownValueIsClampedToTheRangeTheCrownCanReach() {
        XCTAssertEqual(MapZoom.crownValue(forLatitudeDelta: 0.0001), 0, accuracy: 0.000001)
        XCTAssertEqual(MapZoom.crownValue(forLatitudeDelta: 30), 1, accuracy: 0.000001)
    }

    /// The window a double tap asks for is one the crown could have shown itself.
    func testTheFocusWindowIsInsideTheCrownsRange() {
        let span = MapRegion.region(
            around: CLLocationCoordinate2D(latitude: 49.3960, longitude: 15.5910),
            widthMetres: MapRegion.focusMetres,
            heightMetres: MapRegion.focusMetres
        ).span.latitudeDelta

        let value = MapZoom.crownValue(forLatitudeDelta: span)

        XCTAssertGreaterThan(value, 0)
        XCTAssertLessThan(value, 1)
    }

    /// The window opens on the region the app is about, not somewhere else.
    func testTheOpeningWindowMatchesTheRegionOfInterest() {
        let span = MapZoom.span(forCrownValue: MapZoom.initialCrownValue)
        let region = RegionOfInterest.vysocina

        XCTAssertEqual(span.latitudeDelta, region.latitudeSpan, accuracy: 0.3)
        XCTAssertEqual(span.longitudeDelta, region.longitudeSpan, accuracy: 0.5)
    }
}
