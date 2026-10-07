import CoreLocation
import XCTest
@testable import VdvLive

/// The position the watch falls back on when the system will not say where the
/// wearer is.
final class LastKnownPositionStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A throwaway suite so the tests never read or write the real defaults.
        suiteName = "VdvLiveTests.position.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 49.3960, longitude: 15.5910)
    }

    func testStartsEmptyWhenNothingWasEverSeen() {
        XCTAssertNil(LastKnownPositionStore(defaults: defaults).load())
    }

    func testRoundTripsThroughUserDefaults() throws {
        LastKnownPositionStore(defaults: defaults).save(coordinate)

        let reloaded = try XCTUnwrap(LastKnownPositionStore(defaults: defaults).load())

        XCTAssertEqual(reloaded.latitude, 49.3960, accuracy: 0.000001)
        XCTAssertEqual(reloaded.longitude, 15.5910, accuracy: 0.000001)
    }

    func testKeepsOnlyTheLatestPosition() throws {
        let store = LastKnownPositionStore(defaults: defaults)
        store.save(coordinate)
        store.save(CLLocationCoordinate2D(latitude: 50.0810, longitude: 14.4350))

        let reloaded = try XCTUnwrap(store.load())

        XCTAssertEqual(reloaded.latitude, 50.0810, accuracy: 0.000001)
    }

    func testWritesThePositionSoThatAPersonCanReadIt() {
        LastKnownPositionStore(defaults: defaults).save(coordinate)

        XCTAssertEqual(
            defaults.dictionary(forKey: LastKnownPositionStore.defaultKey) as? [String: Double],
            ["latitude": 49.3960, "longitude": 15.5910]
        )
    }

    func testRefusesAPositionTheSystemWouldNotAccept() {
        let store = LastKnownPositionStore(defaults: defaults)

        store.save(CLLocationCoordinate2D(latitude: 91, longitude: 15.5910))
        store.save(CLLocationCoordinate2D(latitude: 49.3960, longitude: 181))

        XCTAssertNil(store.load(), "a position that cannot be placed is not one")
    }

    func testIgnoresSomethingStoredThatIsNotAPosition() {
        defaults.set(["latitude": "not a number", "longitude": 15.5910],
                     forKey: LastKnownPositionStore.defaultKey)
        XCTAssertNil(LastKnownPositionStore(defaults: defaults).load())

        defaults.set(["latitude": 49.3960], forKey: LastKnownPositionStore.defaultKey)
        XCTAssertNil(LastKnownPositionStore(defaults: defaults).load())

        defaults.set(["north": 49.3960, "east": 15.5910], forKey: LastKnownPositionStore.defaultKey)
        XCTAssertNil(LastKnownPositionStore(defaults: defaults).load())

        defaults.set("49.3960,15.5910", forKey: LastKnownPositionStore.defaultKey)
        XCTAssertNil(LastKnownPositionStore(defaults: defaults).load())
    }

    func testIgnoresAStoredPositionThatIsOutOfRange() {
        defaults.set(["latitude": 120.0, "longitude": 15.5910],
                     forKey: LastKnownPositionStore.defaultKey)

        XCTAssertNil(LastKnownPositionStore(defaults: defaults).load())
    }

    func testUsesItsOwnKeyByDefault() {
        XCTAssertNil(LastKnownPositionStore(defaults: defaults).load())
        LastKnownPositionStore(defaults: defaults).save(coordinate)

        XCTAssertNotNil(defaults.dictionary(forKey: "lastKnownPosition"))
    }
}
