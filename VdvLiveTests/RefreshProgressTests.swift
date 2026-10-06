import XCTest
@testable import VdvLive

/// How far a map is from its next refresh, as the phone's header and the watch's
/// hairline both read it.
final class RefreshProgressTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testIsEmptyJustAfterAFetch() {
        XCTAssertEqual(
            RefreshProgress.fraction(lastUpdatedAt: fetchedAt, now: fetchedAt, interval: 15),
            0
        )
    }

    func testFillsUpOverTheInterval() {
        XCTAssertEqual(
            RefreshProgress.fraction(
                lastUpdatedAt: fetchedAt,
                now: fetchedAt.addingTimeInterval(7.5),
                interval: 15
            ),
            0.5
        )
    }

    func testIsFullOnceTheIntervalHasPassed() {
        XCTAssertEqual(
            RefreshProgress.fraction(
                lastUpdatedAt: fetchedAt,
                now: fetchedAt.addingTimeInterval(15),
                interval: 15
            ),
            1
        )
        XCTAssertEqual(
            RefreshProgress.fraction(
                lastUpdatedAt: fetchedAt,
                now: fetchedAt.addingTimeInterval(900),
                interval: 15
            ),
            1
        )
    }

    func testIsFullWhenNothingHasEverLoaded() {
        // Nothing on screen means nothing to count from, so the bar is due rather
        // than empty - an empty bar would promise a refresh that is not coming.
        XCTAssertEqual(
            RefreshProgress.fraction(lastUpdatedAt: nil, now: fetchedAt, interval: 15),
            1
        )
    }

    func testIsEmptyForAFetchThatIsSomehowInTheFuture() {
        // A clock that has just been set backwards should not produce a bar wider
        // than the screen.
        XCTAssertEqual(
            RefreshProgress.fraction(
                lastUpdatedAt: fetchedAt.addingTimeInterval(4),
                now: fetchedAt,
                interval: 15
            ),
            0
        )
    }

    func testIsFullWhenTheIntervalMakesNoSense() {
        XCTAssertEqual(
            RefreshProgress.fraction(lastUpdatedAt: fetchedAt, now: fetchedAt, interval: 0),
            1
        )
        XCTAssertEqual(
            RefreshProgress.fraction(lastUpdatedAt: fetchedAt, now: fetchedAt, interval: -5),
            1
        )
    }

    func testIsFullForAFetchTimeThatIsNotAReasonableUnit() {
        XCTAssertEqual(
            RefreshProgress.fraction(
                lastUpdatedAt: Date(timeIntervalSince1970: .infinity),
                now: fetchedAt,
                interval: 15
            ),
            1
        )
    }
}
