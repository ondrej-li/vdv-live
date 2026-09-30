import XCTest
@testable import VdvMap

final class FavouriteLinesStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A throwaway suite so the tests never read or write the real defaults.
        suiteName = "VdvMapTests.favourites.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStartsEmptyWhenNothingWasEverSaved() {
        let store = UserDefaultsFavouriteLinesStore(defaults: defaults)

        XCTAssertTrue(store.load().isEmpty)
    }

    func testRoundTripsThroughUserDefaults() {
        UserDefaultsFavouriteLinesStore(defaults: defaults).save(FavouriteLines(["420", "337"]))

        let reloaded = UserDefaultsFavouriteLinesStore(defaults: defaults).load()

        XCTAssertEqual(reloaded.orderedForDisplay, ["337", "420"])
    }

    func testStoresTheLinesInDisplayOrder() {
        UserDefaultsFavouriteLinesStore(defaults: defaults)
            .save(FavouriteLines(["420", "18", "337"]))

        XCTAssertEqual(
            defaults.stringArray(forKey: UserDefaultsFavouriteLinesStore.defaultKey),
            ["18", "337", "420"]
        )
    }

    func testSavingAnEmptySetClearsWhatWasThere() {
        let store = UserDefaultsFavouriteLinesStore(defaults: defaults)
        store.save(FavouriteLines(["420"]))

        store.save(FavouriteLines())

        XCTAssertTrue(store.load().isEmpty)
    }

    func testInMemoryStoreStartsEmpty() {
        XCTAssertTrue(InMemoryFavouriteLinesStore().load().isEmpty)
    }

    func testInMemoryStoreKeepsWhatIsSaved() {
        let store = InMemoryFavouriteLinesStore()

        store.save(FavouriteLines(["420"]))

        XCTAssertTrue(store.load().contains("420"))
        XCTAssertEqual(store.saveCount, 1)
    }

    func testInMemoryStoreCanBeSeeded() {
        let store = InMemoryFavouriteLinesStore(lines: FavouriteLines(["420", "337"]))

        XCTAssertEqual(store.load().orderedForDisplay, ["337", "420"])
        XCTAssertEqual(store.saveCount, 0)
    }

    func testRemembersThatOnlyPinnedLinesShouldBeShown() {
        let store = UserDefaultsFavouriteLinesStore(defaults: defaults)
        XCTAssertFalse(store.loadShowsOnlyFavourites())

        store.saveShowsOnlyFavourites(true)

        XCTAssertTrue(UserDefaultsFavouriteLinesStore(defaults: defaults).loadShowsOnlyFavourites())
    }

    func testForgetsThePinnedOnlyModeWhenItIsTurnedOff() {
        let store = UserDefaultsFavouriteLinesStore(defaults: defaults)
        store.saveShowsOnlyFavourites(true)

        store.saveShowsOnlyFavourites(false)

        XCTAssertFalse(store.loadShowsOnlyFavourites())
    }

    func testThePinnedOnlyModeIsIndependentOfWhichLinesArePinned() {
        let store = UserDefaultsFavouriteLinesStore(defaults: defaults)

        store.saveShowsOnlyFavourites(true)
        store.save(FavouriteLines(["420"]))
        store.save(FavouriteLines())

        XCTAssertTrue(store.loadShowsOnlyFavourites())
        XCTAssertTrue(store.load().isEmpty)
    }

    func testInMemoryStoreRemembersThePinnedOnlyMode() {
        let store = InMemoryFavouriteLinesStore()
        XCTAssertFalse(store.loadShowsOnlyFavourites())

        store.saveShowsOnlyFavourites(true)
        XCTAssertTrue(store.loadShowsOnlyFavourites())

        store.saveShowsOnlyFavourites(false)
        XCTAssertFalse(store.loadShowsOnlyFavourites())
    }
}
