import XCTest
@testable import VdvLive

/// The starred stops: what makes two spellings of one stop the same stop, and what a list
/// of them looks like.
final class StarredStopsTests: XCTestCase {
    func testASecondSpellingIsTheSameStop() {
        var stops = StarredStops()
        stops.star("Telč,aut.nádr.")
        stops.star("TELC, aut. nadr.")

        XCTAssertEqual(stops.count, 1)
        XCTAssertTrue(stops.contains("Telč, aut. nádr."))
    }

    func testTogglingUnstarsAndReturnsTheNewState() {
        var stops = StarredStops()

        XCTAssertTrue(stops.toggle("Telč,aut.nádr."))
        XCTAssertFalse(stops.toggle("Telč,aut.nádr."))
        XCTAssertTrue(stops.isEmpty)
    }

    func testTheListIsAlphabetical() {
        let stops = StarredStops(["Žďár", "Jihlava", "Třebíč"])

        XCTAssertEqual(stops.orderedForDisplay, ["Jihlava", "Třebíč", "Žďár"])
    }

    func testAnEmptyNameIsNotAStop() {
        var stops = StarredStops()

        XCTAssertFalse(stops.toggle("   "))
        XCTAssertTrue(stops.isEmpty)
    }

    func testTheStoreRoundTrips() {
        let store = InMemoryStarredStopsStore()
        var stops = StarredStops()
        stops.star("Telč,aut.nádr.")

        store.save(stops)

        XCTAssertEqual(store.load().names, ["Telč,aut.nádr."])
        XCTAssertEqual(store.saveCount, 1)
    }
}
