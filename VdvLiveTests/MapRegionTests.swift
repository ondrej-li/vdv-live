import CoreLocation
import Foundation
import XCTest
@testable import VdvLive

/// The arithmetic behind "show me about ten kilometres around here" at launch, and
/// behind the five a double tap asks for.
final class MapRegionTests: XCTestCase {
    private let jihlava = CLLocationCoordinate2D(latitude: 49.3960, longitude: 15.5910)

    func testTenKilometresIsAboutNineHundredthsOfADegreeOfLatitude() {
        let region = MapRegion.region(
            around: jihlava,
            widthMetres: 10_000,
            heightMetres: 10_000
        )

        XCTAssertEqual(region.span.latitudeDelta, 0.09, accuracy: 0.001)
        XCTAssertEqual(region.center.latitude, 49.3960, accuracy: 1e-9)
        XCTAssertEqual(region.center.longitude, 15.5910, accuracy: 1e-9)
    }

    /// The window a double tap asks for is square on the ground rather than in
    /// degrees: five kilometres across, north to south and east to west.
    func testTheFocusWindowIsFiveKilometresInBothDirections() {
        let region = MapRegion.region(
            around: jihlava,
            widthMetres: MapRegion.focusMetres,
            heightMetres: MapRegion.focusMetres
        )
        let northToSouth = region.span.latitudeDelta * MapScale.metresPerDegreeLatitude
        let eastToWest = region.span.longitudeDelta
            * MapRegion.metresPerDegreeLongitude(at: jihlava.latitude)

        XCTAssertEqual(MapRegion.focusMetres, 5_000)
        XCTAssertEqual(northToSouth, 5_000, accuracy: 1)
        XCTAssertEqual(eastToWest, 5_000, accuracy: 1)
        XCTAssertEqual(region.center.latitude, jihlava.latitude, accuracy: 1e-9)
        XCTAssertEqual(region.center.longitude, jihlava.longitude, accuracy: 1e-9)
    }

    /// Closer than the map opens on, so that a double tap is a deliberate step in
    /// rather than the view it already had.
    func testTheFocusWindowIsCloserThanTheOneTheMapOpensOn() {
        XCTAssertLessThan(MapRegion.focusMetres, MapRegion.currentLocationMetres)
    }

    func testTheSameDistanceNeedsWiderSpansOfLongitudeThisFarNorth() {
        let region = MapRegion.region(
            around: jihlava,
            widthMetres: 10_000,
            heightMetres: 10_000
        )

        // A degree of longitude covers less ground the further from the equator
        // it is, so the same ten kilometres have to be more degrees of it. The
        // ratio between the two spans is the cosine of the latitude.
        XCTAssertGreaterThan(region.span.longitudeDelta, region.span.latitudeDelta)
        XCTAssertEqual(
            region.span.longitudeDelta / region.span.latitudeDelta,
            1 / cos(49.3960 * .pi / 180),
            accuracy: 0.001
        )
    }

    func testWidthAndHeightAreIndependent() {
        let wide = MapRegion.region(around: jihlava, widthMetres: 20_000, heightMetres: 10_000)
        let square = MapRegion.region(around: jihlava, widthMetres: 10_000, heightMetres: 10_000)

        XCTAssertEqual(wide.span.longitudeDelta, square.span.longitudeDelta * 2, accuracy: 1e-9)
        XCTAssertEqual(wide.span.latitudeDelta, square.span.latitudeDelta, accuracy: 1e-9)
    }

    func testTheCentreIsWhereItWasAskedFor() {
        let havlickuvBrod = CLLocationCoordinate2D(latitude: 49.6070, longitude: 15.5810)
        let region = MapRegion.region(
            around: havlickuvBrod,
            widthMetres: 5_000,
            heightMetres: 5_000
        )

        XCTAssertEqual(region.center.latitude, havlickuvBrod.latitude, accuracy: 1e-9)
        XCTAssertEqual(region.center.longitude, havlickuvBrod.longitude, accuracy: 1e-9)
    }

    func testADegreeOfLongitudeShrinksTowardsThePoles() {
        let equator = MapRegion.metresPerDegreeLongitude(at: 0)
        let czechia = MapRegion.metresPerDegreeLongitude(at: 49.5)
        let arctic = MapRegion.metresPerDegreeLongitude(at: 80)

        XCTAssertEqual(equator, MapScale.metresPerDegreeLatitude, accuracy: 1e-9)
        XCTAssertEqual(czechia / equator, cos(49.5 * .pi / 180), accuracy: 1e-9)
        XCTAssertLessThan(arctic, czechia)
    }

    func testThePoleDoesNotProduceAnInfiniteSpan() {
        // Nothing sensible to show at 90° north, but the answer still has to be
        // a number rather than infinity.
        let region = MapRegion.region(
            around: CLLocationCoordinate2D(latitude: 90, longitude: 0),
            widthMetres: 10_000,
            heightMetres: 10_000
        )

        XCTAssertTrue(region.span.longitudeDelta.isFinite)
        XCTAssertGreaterThan(region.span.longitudeDelta, 0)
    }
}
