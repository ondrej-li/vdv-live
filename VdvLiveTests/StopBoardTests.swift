import XCTest
@testable import VdvLive

/// The board at a stop: what belongs on it, in what order, and what a late
/// vehicle does to a row that would otherwise have fallen off the back.
final class StopBoardTests: XCTestCase {
    private let stop = "Telč,aut.nádr."
    private let elsewhere = "Telč,rozc."

    private func call(_ order: Int, at stopName: String? = nil, departing minutes: Int) -> ScheduledCall {
        ScheduledCall(
            order: order,
            stopID: "\(order)",
            stopName: stopName ?? stop,
            arrival: nil,
            departure: TimeOfDay(minutes: minutes),
            distanceKilometres: order,
            isServed: true
        )
    }

    /// One run of a line that calls at the stop once and ends somewhere else.
    private func line(_ code: String, runs: [(service: String, minutes: Int)]) -> LineTimetable {
        LineTimetable(
            lineNumber: code,
            displayNumber: LineCode(raw: code).number,
            routeName: "někam",
            operatorName: nil,
            runs: runs.map { run in
                ScheduledRun(serviceNumber: run.service, calls: [
                    call(1, at: elsewhere, departing: run.minutes - 5),
                    call(2, departing: run.minutes)
                ])
            }
        )
    }

    /// The board the request describes, read at 15:00.
    func testBuildsTheBoardTheRequestDescribes() {
        let board = StopBoard.entries(
            at: stop,
            in: [
                line("764410", runs: [("1", 13 * 60 + 40), ("3", 15 * 60 + 10)]),
                line("764420", runs: [("1", 14 * 60 + 20), ("2", 16 * 60)])
            ],
            delays: ["764410/1": 40, "764410/3": 5, "764420/1": 0],
            now: TimeOfDay(minutes: 15 * 60)
        )

        XCTAssertEqual(
            board.map { "\($0.lineNumber) \($0.scheduled.text) \($0.expected?.text ?? "---")" },
            [
                "764410 13:40 14:20",
                "764420 14:20 14:20",
                "764410 15:10 15:15",
                "764420 16:00 ---"
            ]
        )
        XCTAssertEqual(board.map(\.delayMinutes), [40, 0, 5, nil])
        XCTAssertTrue(board[1].isOnTime, "a vehicle reporting no delay is on time")
        XCTAssertFalse(board[0].isOnTime)
    }

    /// The row that would have fallen off the back is the one that is late: its
    /// expected time is still within the hour that has passed.
    func testALateVehicleIsKeptEvenWhenItIsMoreThanAnHourLate() {
        let board = StopBoard.entries(
            at: stop,
            in: [line("764410", runs: [("1", 7 * 60)])],
            delays: ["764410/1": 8 * 60],
            now: TimeOfDay(minutes: 15 * 60)
        )

        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(board.first?.expected?.text, "15:00")
    }

    /// Without a vehicle reporting, the same row is simply gone: the timetable
    /// says it left at seven.
    func testAnOldRowWithNothingReportingIsGone() {
        let board = StopBoard.entries(
            at: stop,
            in: [line("764410", runs: [("1", 7 * 60)])],
            now: TimeOfDay(minutes: 15 * 60)
        )

        XCTAssertTrue(board.isEmpty)
    }

    func testTheWindowReachesThreeHoursForwardAndNoFurther() {
        let board = StopBoard.entries(
            at: stop,
            in: [line("764410", runs: [("1", 18 * 60), ("2", 18 * 60 + 1)])],
            now: TimeOfDay(minutes: 15 * 60)
        )

        XCTAssertEqual(board.map(\.scheduled.text), ["18:00"])
    }

    func testRunsThatDoNotCallHereAreLeftOut() {
        let board = StopBoard.entries(
            at: stop,
            in: [line("764410", runs: [])],
            now: TimeOfDay(minutes: 15 * 60)
        )

        XCTAssertTrue(board.isEmpty)
    }

    /// A late row sorts by when it will actually be read, so it moves down the
    /// board rather than staying where its timetable put it.
    func testOrderFollowsTheTimeTheRowWillBeReadAt() {
        let board = StopBoard.entries(
            at: stop,
            in: [
                line("764410", runs: [("1", 14 * 60)]),
                line("764420", runs: [("1", 14 * 60 + 10)])
            ],
            delays: ["764410/1": 30],
            now: TimeOfDay(minutes: 15 * 60)
        )

        XCTAssertEqual(board.map(\.lineNumber), ["764420", "764410"])
    }

    /// A line's row keeps the code the archive uses, which is what a delay is
    /// keyed by; the board that shows it formats the passenger number itself.
    func testTheRowCarriesTheArchiveLineNumber() {
        let board = StopBoard.entries(
            at: stop,
            in: [line("764410", runs: [("1", 15 * 60)])],
            now: TimeOfDay(minutes: 15 * 60)
        )

        XCTAssertEqual(board.first?.lineNumber, "764410")
        XCTAssertEqual(LineCode(raw: board.first?.lineNumber ?? "").number, "410")
        XCTAssertEqual(StopBoard.delayKey(line: "764410", service: "1"), "764410/1")
    }
}
