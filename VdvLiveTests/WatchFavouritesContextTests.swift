import XCTest
@testable import VdvLive

/// What the phone puts on each of WatchConnectivity's two channels.
///
/// The distinction matters: the application context is state and is refreshed
/// whenever the defaults change, while a user info transfer is queued and therefore
/// only sent when the list itself changed. Getting the second half wrong would queue
/// a transfer for every map pan the phone writes to its defaults.
final class WatchFavouritesContextTests: XCTestCase {
    private let key = WatchFavouritesContext.key

    func testSendsTheListOnBothChannelsWhenItChanged() {
        let announcement = WatchFavouritesContext.announcement(
            for: FavouriteLines(["841334", "764330"]),
            lastQueued: []
        )

        XCTAssertEqual(announcement.context, ["330", "334"])
        XCTAssertEqual(announcement.queued, ["330", "334"])
    }

    /// What travels is the line as a passenger writes it down, not the code the
    /// feed files it under.
    ///
    /// The watch matches those against the feed's own codes through
    /// `FavouriteLines.contains`, which normalises both sides, so a list sent as
    /// `841334` and one sent as `334` are the same pin - and a change to
    /// `FavouriteLines.normalize` that stopped being idempotent would break the
    /// watch's map rather than its own tests.
    func testTheListThatTravelsIsTheOneAPassengerWouldRecognise() {
        let announcement = WatchFavouritesContext.announcement(
            for: FavouriteLines(["764337"]),
            lastQueued: nil
        )

        XCTAssertEqual(announcement.queued, ["337"])
        XCTAssertTrue(FavouriteLines(announcement.queued ?? []).contains("764337"))
        XCTAssertTrue(FavouriteLines(announcement.queued ?? []).contains("337"))
    }

    func testSendsTheListOnTheFirstAnnouncementOfASession() {
        let announcement = WatchFavouritesContext.announcement(
            for: FavouriteLines(["841334"]),
            lastQueued: nil
        )

        XCTAssertEqual(announcement.queued, ["334"])
    }

    func testRefreshesTheStateWithoutQueueingTheSameListAgain() {
        let announcement = WatchFavouritesContext.announcement(
            for: FavouriteLines(["841334"]),
            lastQueued: ["334"]
        )

        XCTAssertEqual(announcement.context, ["334"])
        XCTAssertNil(announcement.queued, "the list did not change, so nothing is queued")
    }

    func testQueuesAnEmptyListOnceWhenEverythingIsUnpinned() {
        let announcement = WatchFavouritesContext.announcement(
            for: FavouriteLines(),
            lastQueued: ["334"]
        )

        XCTAssertTrue(announcement.context.isEmpty)
        XCTAssertEqual(announcement.queued, [], "unpinning has to reach the watch too")
    }

    func testAPinMadeInAnotherOrderIsTheSameList() {
        // The order is the displayed one rather than the order the pins were made
        // in, so re-pinning the same lines the other way round queues nothing.
        let announcement = WatchFavouritesContext.announcement(
            for: FavouriteLines(["841334", "764330"]),
            lastQueued: ["330", "334"]
        )

        XCTAssertNil(announcement.queued)
    }

    func testCarriesTheListUnderTheKeyTheWatchReads() throws {
        let announcement = WatchFavouritesContext.announcement(
            for: FavouriteLines(["841334"]),
            lastQueued: nil
        )
        let sent: [String: Any] = [key: try XCTUnwrap(announcement.queued)]
        let raw = try XCTUnwrap(sent["favouriteLines"] as? [String])

        XCTAssertEqual(raw, ["334"])
    }
}
