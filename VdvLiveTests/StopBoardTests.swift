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
    /// - Parameter startMinutesBefore: how long the run has been going by the time it
    ///   reaches this stop, which is what decides whether a vehicle can be on it.
    private func line(_ code: String,
                      runs: [(service: String, minutes: Int)],
                      startMinutesBefore: Int = 5) -> LineTimetable {
        LineTimetable(
            lineNumber: code,
            displayNumber: LineCode(raw: code).number,
            routeName: "někam",
            operatorName: nil,
            runs: runs.map { run in
                ScheduledRun(serviceNumber: run.service, calls: [
                    call(1, at: elsewhere, departing: run.minutes - startMinutesBefore),
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

    /// The feed reports vehicles by line, not by run, so a board falls back to the
    /// line's delay - but a run's own delay wins when there is one.
    func testALineWideDelayIsUsedWhenTheRunItselfIsNotNamed() {
        let board = StopBoard.entries(
            at: stop,
            in: [line("764410", runs: [("7", 15 * 60)])],
            delays: ["764410": 12],
            now: TimeOfDay(minutes: 15 * 60)
        )

        XCTAssertEqual(board.first?.expected?.text, "15:12")
        XCTAssertEqual(board.first?.delayMinutes, 12)
    }

    func testARunsOwnDelayOutranksItsLine() {
        let board = StopBoard.entries(
            at: stop,
            in: [line("764410", runs: [("7", 15 * 60)])],
            delays: ["764410": 12, "764410/7": 3],
            now: TimeOfDay(minutes: 15 * 60)
        )

        XCTAssertEqual(board.first?.expected?.text, "15:03")
    }

    /// The bug in #107: the vehicle out there now is ten minutes late, and every later
    /// service of the same line wore that delay on a departure that had not left yet.
    func testAServiceThatHasNotLeftDoesNotInheritTheLinesDelay() {
        let board = StopBoard.entries(
            at: stop,
            in: [line("764410", runs: [("1", 14 * 60), ("2", 18 * 60)], startMinutesBefore: 60)],
            delays: ["764410": 10],
            now: TimeOfDay(minutes: 15 * 60)
        )

        XCTAssertEqual(board.map { $0.expected?.text ?? "—" }, ["14:10", "—"])
    }

    /// Only one vehicle per line is being reported, so only one row of that line may
    /// claim the delay - the one nearest the reader.
    func testOnlyTheNearestRowOfALineTakesTheLinesDelay() {
        let board = StopBoard.entries(
            at: stop,
            in: [line("764410", runs: [("1", 15 * 60 + 20), ("2", 16 * 60 + 40)],
                      startMinutesBefore: 120)],
            delays: ["764410": 5],
            now: TimeOfDay(minutes: 15 * 60)
        )

        XCTAssertEqual(board.map { $0.expected?.text ?? "—" }, ["15:25", "—"])
    }

    /// A run that ended hours ago is not the vehicle reporting a delay, so its row keeps
    /// the timetable's time - and falls off the board, where it belongs.
    func testARunThatEndedLongAgoTakesNoDelay() {
        let board = StopBoard.entries(
            at: stop,
            in: [line("764410", runs: [("1", 12 * 60)])],
            delays: ["764410": 240],
            now: TimeOfDay(minutes: 15 * 60)
        )

        XCTAssertTrue(board.isEmpty, "12:00 with no delay of its own is outside the hour")
    }

    /// A board says where the bus is going, not just which line it is. Two runs of
    /// one line can end in different places, and that difference is the whole reason
    /// a passenger reads the board.
    func testARowCarriesTheDestinationOfItsRun() {
        let timetable = LineTimetable(
            lineNumber: "764410",
            displayNumber: "410",
            routeName: "Třešť-Brtnice-Okříšky-Radonín",
            operatorName: nil,
            runs: [
                ScheduledRun(serviceNumber: "1", calls: [
                    call(1, departing: 15 * 60 + 5),
                    call(2, at: "Telč,aut.nádr.", departing: 15 * 60 + 40)
                ]),
                ScheduledRun(serviceNumber: "2", calls: [
                    call(1, departing: 15 * 60 + 20),
                    call(2, at: "Třešť,nám.", departing: 15 * 60 + 55)
                ])
            ]
        )

        let board = StopBoard.entries(at: stop, in: [timetable], now: TimeOfDay(minutes: 15 * 60))

        XCTAssertEqual(board.map(\.destination), ["Telč,aut.nádr.", "Třešť,nám."])
    }

    /// The board opens where the reader is standing, so the clock has to be readable
    /// off the device's own time zone.
    func testReadsTheClockOffADate() throws {
        var calendar = Calendar(identifier: .gregorian)
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Prague"))
        calendar.timeZone = zone
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 21, hour: 15, minute: 7
        )))

        XCTAssertEqual(TimeOfDay(date, calendar: calendar).text, "15:07")
        XCTAssertEqual(TimeOfDay(date, calendar: calendar).minutes, 15 * 60 + 7)
    }
}
