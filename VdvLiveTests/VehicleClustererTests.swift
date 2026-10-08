import CoreLocation
import MapKit
import XCTest
@testable import VdvLive

/// Grouping vehicles that are close together, and leaving the rest alone.
final class VehicleClustererTests: XCTestCase {
    /// A square a degree wide, which is far bigger than any radius under test.
    private let viewport = RegionOfInterest.BoundingBox(region: Fixture.squareRegion)

    /// Two vehicles about 67 m apart, and a third about 1.1 km north of them.
    private let close = Fixture.vehicle(id: 1, latitude: 49.4000, longitude: 15.6000)
    private let closer = Fixture.vehicle(id: 2, latitude: 49.4006, longitude: 15.6000)
    private let distant = Fixture.vehicle(id: 3, latitude: 49.4100, longitude: 15.6000)

    private func markers(_ vehicles: [Vehicle], radiusMetres: Double) -> [VehicleCluster] {
        VehicleClusterer.markers(vehicles, in: viewport, radiusMetres: radiusMetres)
    }

    // MARK: - The radius

    func testARadiusOfZeroLeavesEveryVehicleOnItsOwn() {
        let markers = markers([close, closer, distant], radiusMetres: 0)

        XCTAssertEqual(markers.count, 3)
        XCTAssertEqual(markers.map(\.id), ["vehicle:1", "vehicle:2", "vehicle:3"])
        XCTAssertEqual(markers.compactMap { $0.singleVehicle?.id }, [1, 2, 3])
    }

    func testVehiclesWithinTheRadiusShareAMarker() {
        let markers = markers([close, closer, distant], radiusMetres: 100)

        XCTAssertEqual(markers.count, 2)
        let group = try? XCTUnwrap(markers.first)
        XCTAssertEqual(group?.count, 2)
        XCTAssertEqual(group?.vehicles.map(\.id), [1, 2])
        XCTAssertNil(group?.singleVehicle, "two vehicles on one marker is not one vehicle")
    }

    func testVehiclesFurtherApartThanTheRadiusStayApart() {
        // 1.1 km is more than the radius, so the third vehicle keeps its own
        // marker even when the first two are drawn together. A group of one is
        // still a marker of its own, labelled as a group.
        let markers = markers([close, closer, distant], radiusMetres: 1_000)

        XCTAssertEqual(markers.map(\.id), ["cluster:1", "cluster:3"])
        XCTAssertEqual(markers.map(\.count), [2, 1])
        XCTAssertEqual(markers.last?.singleVehicle?.id, 3)
    }

    func testAWideEnoughRadiusDrawsEverythingTogether() {
        let markers = markers([close, closer, distant], radiusMetres: 1_200)

        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.count, 3)
    }

    // MARK: - A crowded map

    /// The region as a desktop window shows it: 1.1 degrees of latitude, which is
    /// 122 km.
    private let regionSpan = MKCoordinateSpan(latitudeDelta: 1.1, longitudeDelta: 1.5)

    /// A street: about 8 km across.
    private let streetSpan = MKCoordinateSpan(latitudeDelta: 0.07, longitudeDelta: 0.1)

    func testTheSettingIsUsedWhileTheMapIsNotCrowded() {
        XCTAssertEqual(
            VehicleClusterer.groupingRadiusMetres(setting: 250, vehicles: 40, span: regionSpan),
            250
        )
        XCTAssertEqual(
            VehicleClusterer.groupingRadiusMetres(setting: 250, vehicles: 100, span: regionSpan),
            250,
            "a hundred vehicles is not yet a crowd"
        )
    }

    func testACrowdIsGroupedEvenWithTheSettingOff() {
        let radius = VehicleClusterer.groupingRadiusMetres(setting: 0, vehicles: 610, span: regionSpan)

        XCTAssertEqual(radius, 1.1 * MapScale.metresPerDegreeLatitude / 40, accuracy: 1)
        XCTAssertEqual(radius, 3_056, accuracy: 2, "a fortieth of the region is about 3 km")
    }

    func testTheCrowdedRadiusIsTheSameSizeAtEveryZoom() {
        let region = VehicleClusterer.groupingRadiusMetres(setting: 0, vehicles: 610, span: regionSpan)
        let street = VehicleClusterer.groupingRadiusMetres(setting: 0, vehicles: 610, span: streetSpan)

        XCTAssertEqual(street / region, 0.07 / 1.1, accuracy: 0.001)
        XCTAssertEqual(street, 194, accuracy: 1)
    }

    func testARadiusTheUserChoseStillWinsWhenItIsWider() {
        XCTAssertEqual(
            VehicleClusterer.groupingRadiusMetres(setting: 5_000, vehicles: 610, span: regionSpan),
            5_000
        )
    }

    func testACrowdOfVehiclesIsDrawnAsFarFewerMarkers() {
        // Four hundred vehicles about a kilometre apart, which is fifteen times
        // what the test case draws elsewhere.
        let vehicles = Fixture.grid(count: 20, spacing: 0.01)
        let radius = VehicleClusterer.groupingRadiusMetres(
            setting: 0,
            vehicles: vehicles.count,
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )

        let markers = markers(vehicles, radiusMetres: radius)

        XCTAssertLessThan(markers.count, vehicles.count / 2)
        XCTAssertGreaterThan(markers.count, 10, "the region is not one dot")
    }

    // MARK: - The anchor

    func testAGroupIsNamedAfterItsAnchorSoItsIdentitySurvives() {
        let before = markers([close, closer], radiusMetres: 100)
        let after = markers(
            [close, closer, Fixture.vehicle(id: 4, latitude: 49.4001, longitude: 15.6001)],
            radiusMetres: 100
        )

        XCTAssertEqual(before.map(\.id), ["cluster:1"])
        XCTAssertEqual(after.map(\.id), ["cluster:1"], "the anchor did not change, so the marker did not either")
        XCTAssertEqual(after.first?.count, 3)
    }

    func testTheAnchorIsTheLowestNumberedVehicleWhateverOrderTheFeedSends() {
        let shuffled = [distant, closer, close]

        let markers = markers(shuffled, radiusMetres: 100)

        XCTAssertEqual(markers.map(\.id), ["cluster:1", "cluster:3"])
        XCTAssertEqual(markers.first?.representative.id, 1)
        XCTAssertEqual(markers.first?.vehicles.map(\.id), [1, 2], "members are kept in server order")
    }

    func testGroupingIsMeasuredAgainstTheAnchorAndNotChained() {
        // 1 and 2 are 67 m apart and 2 and 3 are 89 m apart, but 1 and 3 are
        // 156 m apart. With a 100 m radius the third is measured against the
        // anchor - the first vehicle - and so stays out on its own.
        let second = Fixture.vehicle(id: 2, latitude: 49.4006, longitude: 15.6000)
        let third = Fixture.vehicle(id: 3, latitude: 49.4014, longitude: 15.6000)

        let markers = markers([close, second, third], radiusMetres: 100)

        XCTAssertEqual(markers.map(\.id), ["cluster:1", "cluster:3"])
        XCTAssertEqual(markers.map(\.count), [2, 1])
    }

    // MARK: - The viewport

    func testVehiclesOutsideTheViewportAreLeftOut() {
        let offScreen = Fixture.vehicle(id: 9, latitude: 50.5, longitude: 15.6)

        let markers = markers([close, offScreen], radiusMetres: 0)

        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.singleVehicle?.id, 1)
    }

    func testAnEmptyPayloadProducesNoMarkers() {
        XCTAssertTrue(markers([], radiusMetres: 100).isEmpty)
    }

    // MARK: - The marker itself

    func testAGroupSitsAtTheAverageOfItsMembers() throws {
        let marker = try XCTUnwrap(markers([close, closer], radiusMetres: 100).first)

        XCTAssertEqual(marker.coordinate.latitude, 49.4003, accuracy: 0.0000001)
        XCTAssertEqual(marker.coordinate.longitude, 15.6000, accuracy: 0.0000001)
    }

    func testAMarkerForOneVehicleKeepsItsExactPositionAndNamesItsLine() throws {
        let marker = try XCTUnwrap(markers([close], radiusMetres: 100).first)

        XCTAssertEqual(marker.coordinate.latitude, 49.4000, accuracy: 0.0000001)
        XCTAssertEqual(marker.singleVehicle?.id, 1)
        // 841334 is operator 841 running line 334.
        XCTAssertEqual(marker.title, String(format: String(localized: "Line %@"), "334"))
    }

    func testAGroupSaysHowManyVehiclesItStandsFor() throws {
        let marker = try XCTUnwrap(markers([close, closer], radiusMetres: 100).first)

        XCTAssertEqual(marker.title, String(format: String(localized: "%lld vehicles"), 2))
    }

    func testDominantTractionWinsOnCountAndBreaksTiesDeterministically() {
        let buses = [
            Fixture.vehicle(id: 1, latitude: 49.4, longitude: 15.6, traction: .bus),
            Fixture.vehicle(id: 2, latitude: 49.4, longitude: 15.6, traction: .bus),
            Fixture.vehicle(id: 3, latitude: 49.4, longitude: 15.6, traction: .train)
        ]
        XCTAssertEqual(markers(buses, radiusMetres: 100).first?.dominantTraction, .bus)

        let tie = [
            Fixture.vehicle(id: 4, latitude: 49.4, longitude: 15.6, traction: .train),
            Fixture.vehicle(id: 5, latitude: 49.4, longitude: 15.6, traction: .bus)
        ]
        XCTAssertEqual(markers(tie, radiusMetres: 100).first?.dominantTraction, .bus)
    }

    func testEveryVisibleVehicleEndsUpInExactlyOneMarker() {
        let vehicles = (0..<50).map { index in
            Fixture.vehicle(id: index, latitude: 49.0 + Double(index) * 0.01, longitude: 15.2)
        }

        let markers = markers(vehicles, radiusMetres: 500)
        let grouped = markers.flatMap { $0.vehicles.map(\.id) }.sorted()

        XCTAssertEqual(grouped, vehicles.map(\.id).sorted())
    }

    // MARK: - Distance

    func testDistanceUsesTheLatitudeAndTheShrinkingDegreeOfLongitude() {
        let origin = CLLocationCoordinate2D(latitude: 49.4, longitude: 15.6)

        // A thousandth of a degree of latitude is 111 m anywhere.
        let north = CLLocationCoordinate2D(latitude: 49.401, longitude: 15.6)
        XCTAssertEqual(VehicleClusterer.metres(from: origin, to: north), 111.1, accuracy: 0.5)

        // The same thousandth of a degree east is shorter: longitude shrinks
        // towards the poles by the cosine of the latitude.
        let east = CLLocationCoordinate2D(latitude: 49.4, longitude: 15.601)
        XCTAssertEqual(VehicleClusterer.metres(from: origin, to: east), 72.3, accuracy: 0.5)

        XCTAssertEqual(VehicleClusterer.metres(from: origin, to: origin), 0, accuracy: 0.0000001)
    }
}
