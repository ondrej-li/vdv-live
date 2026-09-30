import CoreLocation
import MapKit
import SwiftUI
import XCTest
@testable import VdvMap

final class VehicleDelayTests: XCTestCase {
    func testSentinelMeansUnknown() {
        XCTAssertEqual(VehicleDelay(rawMinutes: VehicleDelay.unknownSentinel), .unknown)
        XCTAssertEqual(VehicleDelay(rawMinutes: Int(Int32.min)), .unknown)
        XCTAssertFalse(VehicleDelay(rawMinutes: Int(Int32.min)).isKnown)
    }

    func testZeroIsAKnownOnTimeValue() {
        let delay = VehicleDelay(rawMinutes: 0)

        XCTAssertTrue(delay.isKnown)
        XCTAssertEqual(delay.minutes, 0)
        XCTAssertEqual(delay.displayText, String(localized: "on time"))
    }

    func testFormatsLateAndEarlyVehicles() {
        XCTAssertEqual(
            VehicleDelay(rawMinutes: 5).displayText,
            String(format: String(localized: "+%lld min"), 5)
        )
        XCTAssertEqual(
            VehicleDelay(rawMinutes: 1).displayText,
            String(format: String(localized: "+%lld min"), 1)
        )
        XCTAssertEqual(
            VehicleDelay(rawMinutes: -68).displayText,
            String(format: String(localized: "%lld min"), -68)
        )
        XCTAssertEqual(VehicleDelay.unknown.displayText, String(localized: "no data"))
    }

    func testColourFlagsHowFarOffScheduleTheVehicleIs() {
        XCTAssertEqual(VehicleDelay(rawMinutes: 0).tint, .green)
        XCTAssertEqual(VehicleDelay(rawMinutes: -68).tint, .green)
        XCTAssertEqual(VehicleDelay(rawMinutes: 2).tint, .orange)
        XCTAssertEqual(VehicleDelay(rawMinutes: 5).tint, .red)
        XCTAssertEqual(VehicleDelay(rawMinutes: 357).tint, .red)
    }
}

final class TractionTests: XCTestCase {
    func testParsesServerValues() {
        XCTAssertEqual(Traction(serverValue: "BUS"), .bus)
        XCTAssertEqual(Traction(serverValue: "TRAIN"), .train)
        XCTAssertEqual(Traction(serverValue: "UNKNOWN"), .unknown)
    }

    func testParsesServerValuesCaseInsensitivelyAndTrims() {
        XCTAssertEqual(Traction(serverValue: " bus "), .bus)
        XCTAssertEqual(Traction(serverValue: "tram"), .tram)
    }

    func testFallsBackToUnknownForValuesTheFeedMightAddLater() {
        XCTAssertEqual(Traction(serverValue: "METRO"), .unknown)
        XCTAssertEqual(Traction(serverValue: ""), .unknown)
    }

    func testSortOrderMatchesMenuOrder() {
        let sorted = Traction.allCases.sorted { $0.sortIndex < $1.sortIndex }

        XCTAssertEqual(sorted.first, .bus)
        XCTAssertEqual(sorted.last, .unknown)
        XCTAssertEqual(Set(sorted), Set(Traction.allCases))
    }
}

final class RegionOfInterestTests: XCTestCase {
    func testRegionCoversJihlavaAndTrebic() {
        XCTAssertTrue(
            RegionOfInterest.vysocina.contains(
                CLLocationCoordinate2D(latitude: 49.3960, longitude: 15.5910)
            )
        )
        XCTAssertTrue(
            RegionOfInterest.vysocina.contains(
                CLLocationCoordinate2D(latitude: 49.2150, longitude: 15.8810)
            )
        )
    }

    func testRegionExcludesPlacesOutsideIt() {
        // Prague, roughly 80 km north of the region.
        XCTAssertFalse(
            RegionOfInterest.vysocina.contains(
                CLLocationCoordinate2D(latitude: 50.0880, longitude: 14.4210)
            )
        )
        // Vienna, south of the region.
        XCTAssertFalse(
            RegionOfInterest.vysocina.contains(
                CLLocationCoordinate2D(latitude: 48.2082, longitude: 16.3738)
            )
        )
        // Olomouc, east of it.
        XCTAssertFalse(
            RegionOfInterest.vysocina.contains(
                CLLocationCoordinate2D(latitude: 49.5945, longitude: 17.2510)
            )
        )
    }

    func testMapRegionIsCentredOnTheBox() {
        let region = RegionOfInterest.vysocina.region

        XCTAssertEqual(region.center.latitude, 49.40, accuracy: 0.001)
        XCTAssertEqual(region.center.longitude, 15.675, accuracy: 0.001)
        XCTAssertGreaterThan(region.span.latitudeDelta, RegionOfInterest.vysocina.latitudeSpan)
        XCTAssertGreaterThan(region.span.longitudeDelta, RegionOfInterest.vysocina.longitudeSpan)
    }
}
