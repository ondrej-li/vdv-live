import XCTest
@testable import VdvLive

/// What the app keeps in its own defaults has to survive the move into the group
/// the widgets read, or an update would lose every pin and star.
final class SharedContainerTests: XCTestCase {
    private var appSuite: String!
    private var sharedSuite: String!
    private var app: UserDefaults!
    private var shared: UserDefaults!

    override func setUp() {
        super.setUp()
        appSuite = "VdvLiveTests.shared.app.\(UUID().uuidString)"
        sharedSuite = "VdvLiveTests.shared.group.\(UUID().uuidString)"
        app = UserDefaults(suiteName: appSuite)
        shared = UserDefaults(suiteName: sharedSuite)
    }

    override func tearDown() {
        app.removePersistentDomain(forName: appSuite)
        shared.removePersistentDomain(forName: sharedSuite)
        app = nil
        shared = nil
        appSuite = nil
        sharedSuite = nil
        super.tearDown()
    }

    func testCopiesWhatTheAppHadBeforeTheGroup() {
        app.set(["420", "337"], forKey: SharedContainer.Key.favouriteLines)
        app.set(["Telč,aut.nádr."], forKey: SharedContainer.Key.starredStops)

        SharedContainer.copyDefaultsFromAppIfNeeded(from: app, to: shared)

        XCTAssertEqual(shared.stringArray(forKey: SharedContainer.Key.favouriteLines), ["420", "337"])
        XCTAssertEqual(shared.stringArray(forKey: SharedContainer.Key.starredStops), ["Telč,aut.nádr."])
    }

    func testNeverOverwritesWhatTheGroupAlreadyHas() {
        app.set(["420"], forKey: SharedContainer.Key.favouriteLines)
        shared.set(["337"], forKey: SharedContainer.Key.favouriteLines)

        SharedContainer.copyDefaultsFromAppIfNeeded(from: app, to: shared)

        XCTAssertEqual(shared.stringArray(forKey: SharedContainer.Key.favouriteLines), ["337"])
    }

    func testIsIdempotent() {
        app.set(["420"], forKey: SharedContainer.Key.favouriteLines)

        SharedContainer.copyDefaultsFromAppIfNeeded(from: app, to: shared)
        shared.set(["337"], forKey: SharedContainer.Key.favouriteLines)
        SharedContainer.copyDefaultsFromAppIfNeeded(from: app, to: shared)

        XCTAssertEqual(shared.stringArray(forKey: SharedContainer.Key.favouriteLines), ["337"])
    }

    func testCopiesThePositionToo() {
        LastKnownPositionStore(defaults: app).save(.init(latitude: 49.1842, longitude: 15.4528))

        SharedContainer.copyDefaultsFromAppIfNeeded(from: app, to: shared)

        let copied = LastKnownPositionStore(defaults: shared).load()
        XCTAssertEqual(copied?.latitude ?? 0, 49.1842, accuracy: 0.000001)
    }

    func testTheKeysItCopiesAreTheOnesTheWidgetsRead() {
        XCTAssertTrue(SharedContainer.Key.all.contains(SharedContainer.Key.favouriteLines))
        XCTAssertTrue(SharedContainer.Key.all.contains(SharedContainer.Key.starredStops))
        XCTAssertTrue(SharedContainer.Key.all.contains(SharedContainer.Key.lastKnownPosition))
    }
}
