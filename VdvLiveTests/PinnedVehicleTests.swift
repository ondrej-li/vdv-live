import XCTest
@testable import VdvLive

/// What a map of the pinned lines draws, out of a payload that may be older than
/// the pins it is drawn through.
///
/// This is the rule that lets the watch show something with no network: the payload
/// kept from an earlier launch is used, but only for the lines pinned *now*, so
/// pinning or unpinning a line on the phone changes the map even when the feed
/// cannot be reached.
final class PinnedVehicleTests: XCTestCase {
    private func payload() -> VehiclePayload {
        VehiclePayload(
            vehicles: [
                Fixture.vehicle(id: 1, line: "841334"),
                Fixture.vehicle(id: 2, line: "764330", delay: .minutes(12)),
                Fixture.vehicle(id: 3, line: "5435405", delay: .unknown),
                Fixture.vehicle(id: 4, line: "999999", latitude: 0, longitude: 0)
            ],
            skippedRecordCount: 0,
            unlocatableRecordCount: 1
        )
    }

    func testDrawsOnlyThePinnedLines() {
        let drawn = payload().vehicles(onPinnedLines: FavouriteLines(["841334", "764330"]))

        XCTAssertEqual(drawn.map(\.id), [1, 2])
    }

    func testDrawsNothingWhenNothingIsPinned() {
        XCTAssertTrue(payload().vehicles(onPinnedLines: FavouriteLines()).isEmpty)
    }

    func testUsesThePinsOfNowRatherThanTheOnesThePayloadWasFetchedWith() {
        // A line pinned while the watch was offline still appears, because the
        // payload holds every line the feed reported and not just the old pins.
        let afterPinning = payload().vehicles(
            onPinnedLines: FavouriteLines(["841334", "5435405"])
        )
        XCTAssertEqual(afterPinning.map(\.id), [1, 3])

        // And a line unpinned in the meantime goes, even though the payload still
        // has its vehicle.
        let afterUnpinning = payload().vehicles(onPinnedLines: FavouriteLines(["841334"]))
        XCTAssertEqual(afterUnpinning.map(\.id), [1])
    }

    func testLeavesOutAVehicleTheFeedCouldNotPlace() {
        // The feed publishes what it cannot locate as `0, 0`, which would land in
        // the Gulf of Guinea - pinned or not, it is not drawn.
        let drawn = payload().vehicles(onPinnedLines: FavouriteLines(["999999"]))

        XCTAssertTrue(drawn.isEmpty)
    }

    func testKeepsTheDelayTheFeedSent() {
        let drawn = payload().vehicles(onPinnedLines: FavouriteLines(["764330", "5435405"]))

        XCTAssertEqual(drawn.map(\.delay), [.minutes(12), .unknown])
    }

    func testKeepsEveryFieldOfTheVehicle() throws {
        let drawn = payload().vehicles(onPinnedLines: FavouriteLines(["764330"]))
        let vehicle = try XCTUnwrap(drawn.first)

        XCTAssertEqual(vehicle.id, 2)
        XCTAssertEqual(vehicle.line, "764330")
        XCTAssertEqual(vehicle.latitude, 49.3960)
        XCTAssertEqual(vehicle.longitude, 15.5910)
        XCTAssertEqual(vehicle.destination, "Jihlava,aut.nádr.")
        XCTAssertEqual(vehicle.traction, .bus)
    }
}
