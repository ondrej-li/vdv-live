import XCTest
@testable import VdvLive

final class LineSearchTests: XCTestCase {
    private func running(_ line: String) -> LineSummary {
        LineSummary(line: line, licenceAreaCode: nil, vehicleCount: 2, traction: .bus)
    }

    func testAnEmptyQueryOffersNothing() {
        XCTAssertTrue(LineSearch.matches("", pinned: [running("337")], running: [running("337")]).isEmpty)
        XCTAssertTrue(LineSearch.matches("   ", pinned: [running("337")], running: []).isEmpty)
    }

    func testMatchesTheDigitsOfTheLine() {
        let found = LineSearch.matches("33", pinned: [], running: [running("337"), running("812")])
        XCTAssertEqual(found.map(\.line), ["337"])
    }

    /// A pinned line comes first even when the feed is reporting it too, and it still
    /// appears only once: the list is a set of places to go, not of facts about lines.
    func testAPinnedLineAppearsOnceAndFirst() {
        let found = LineSearch.matches(
            "33",
            pinned: [.idle("337"), .idle("33")],
            running: [running("33"), running("337"), running("338")]
        )

        XCTAssertEqual(found.map(\.line), ["337", "33", "338"])
    }

    /// The pinned line that is not running is still offered: somebody typed its number
    /// because they want to watch it.
    func testAPinnedLineThatIsNotRunningIsStillOffered() {
        let found = LineSearch.matches("812", pinned: [.idle("812")], running: [])
        XCTAssertEqual(found.map(\.line), ["812"])
        XCTAssertEqual(found.first?.vehicleCount, 0)
    }

    func testStopsAtTheLimit() {
        let many = (0..<40).map { running("\(700 + $0)") }
        XCTAssertEqual(LineSearch.matches("7", pinned: [], running: many).count, LineSearch.limit)
    }

    func testNoMatchIsNoMatch() {
        XCTAssertTrue(LineSearch.matches("999", pinned: [.idle("337")], running: [running("420")]).isEmpty)
    }
}
