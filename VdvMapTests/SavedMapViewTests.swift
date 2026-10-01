import CoreLocation
import MapKit
import XCTest
@testable import VdvMap

/// The viewport the lock button remembers, and what it refuses to remember.
final class SavedMapViewTests: XCTestCase {
    private var jihlavaRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 49.3960, longitude: 15.5910),
            span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.138)
        )
    }

    func testARegionSurvivesBeingStoredAndRestored() throws {
        let saved = try XCTUnwrap(SavedMapView(region: jihlavaRegion))
        let restored = saved.region

        XCTAssertEqual(restored.center.latitude, 49.3960, accuracy: 1e-9)
        XCTAssertEqual(restored.center.longitude, 15.5910, accuracy: 1e-9)
        XCTAssertEqual(restored.span.latitudeDelta, 0.09, accuracy: 1e-9)
        XCTAssertEqual(restored.span.longitudeDelta, 0.138, accuracy: 1e-9)
    }

    func testASpanOfNothingIsRefused() {
        let flat = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 49.3960, longitude: 15.5910),
            span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0.138)
        )

        XCTAssertNil(SavedMapView(region: flat))
    }

    func testASpanThatIsNotANumberIsRefused() {
        let broken = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 49.3960, longitude: 15.5910),
            span: MKCoordinateSpan(latitudeDelta: .nan, longitudeDelta: .infinity)
        )

        XCTAssertNil(SavedMapView(region: broken))
    }

    func testACoordinateOffThePlanetIsRefused() {
        let nowhere = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 100, longitude: 15.5910),
            span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.138)
        )

        XCTAssertNil(SavedMapView(region: nowhere))
    }

    func testTheStoredShapeSurvivesAUserDefaultsRoundTrip() throws {
        let saved = try XCTUnwrap(SavedMapView(region: jihlavaRegion))

        let restored = try XCTUnwrap(SavedMapView(storedValues: saved.storedValues))

        XCTAssertEqual(restored, saved)
    }

    func testAnIncompleteStoredValueIsIgnored() {
        XCTAssertNil(
            SavedMapView(storedValues: ["latitude": 49.3960, "longitude": 15.5910])
        )
    }

    func testAnUnreadableStoredValueIsIgnored() {
        XCTAssertNil(
            SavedMapView(storedValues: [
                "latitude": .nan,
                "longitude": 15.5910,
                "latitudeDelta": 0.09,
                "longitudeDelta": 0.138
            ])
        )
    }
}
