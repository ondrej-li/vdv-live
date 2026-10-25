import CoreLocation
import XCTest
@testable import VdvLive

final class MapHeadingTests: XCTestCase {
    func testNorthIsNorthUp() {
        XCTAssertFalse(MapHeading.isTurnedAwayFromNorth(0))
        XCTAssertFalse(MapHeading.isTurnedAwayFromNorth(360))
        XCTAssertFalse(MapHeading.isTurnedAwayFromNorth(720))
    }

    /// The whole reason this is not a plain comparison: a degree short of north is a
    /// degree away from it, not 359 degrees away from it.
    func testJustShortOfNorthIsStillNorthUp() {
        XCTAssertFalse(MapHeading.isTurnedAwayFromNorth(359.5))
        XCTAssertFalse(MapHeading.isTurnedAwayFromNorth(-0.5))
        XCTAssertFalse(MapHeading.isTurnedAwayFromNorth(0.5))
    }

    func testATurnIsATurn() {
        XCTAssertTrue(MapHeading.isTurnedAwayFromNorth(90))
        XCTAssertTrue(MapHeading.isTurnedAwayFromNorth(-90))
        XCTAssertTrue(MapHeading.isTurnedAwayFromNorth(180))
        XCTAssertTrue(MapHeading.isTurnedAwayFromNorth(350))
    }

    /// A heading the camera has not reported yet must not put a compass on screen.
    func testAnUnreadableHeadingLeavesTheMapNorthUp() {
        XCTAssertFalse(MapHeading.isTurnedAwayFromNorth(.nan))
        XCTAssertFalse(MapHeading.isTurnedAwayFromNorth(.infinity))
    }
}
