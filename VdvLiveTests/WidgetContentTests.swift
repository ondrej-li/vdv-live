import CoreLocation
import XCTest
@testable import VdvLive

/// What a board widget shows, and what it says when it cannot show a board at all.
final class WidgetContentTests: XCTestCase {
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

    /// One run that calls at the stop once and ends somewhere else.
    private func line(_ code: String, departing minutes: Int, service: String = "1") -> LineTimetable {
        LineTimetable(
            lineNumber: code,
            displayNumber: LineCode(raw: code).number,
            routeName: "někam",
            operatorName: nil,
            runs: [
                ScheduledRun(serviceNumber: service, calls: [
                    call(1, at: elsewhere, departing: minutes - 5),
                    call(2, departing: minutes)
                ])
            ]
        )
    }

    func testWithoutAStopThereIsNothingToShow() {
        XCTAssertEqual(WidgetContent.board(stopName: nil, timetables: [], now: TimeOfDay(minutes: 900)),
                       .needsStop)
        XCTAssertEqual(WidgetContent.board(stopName: "", timetables: [], now: TimeOfDay(minutes: 900)),
                       .needsStop)
    }

    func testWithoutTimetablesTheBoardSaysSo() {
        XCTAssertEqual(WidgetContent.board(stopName: stop, timetables: nil, now: TimeOfDay(minutes: 900)),
                       .needsTimetables)
    }

    func testShowsTheSoonestRowsFirstAndDropsWhatHasGone() {
        let state = WidgetContent.board(
            stopName: stop,
            timetables: [
                line("764410", departing: 14 * 60 + 50),
                line("764420", departing: 15 * 60 + 10)
            ],
            now: TimeOfDay(minutes: 15 * 60)
        )

        guard case .board(let name, let rows) = state else {
            return XCTFail("Expected a board, got \(state)")
        }
        XCTAssertEqual(name, stop)
        XCTAssertEqual(rows.map { "\(LineCode(raw: $0.lineNumber).number) \($0.scheduled.text)" },
                       ["420 15:10"])
    }

    func testARowLeavesTheBoardWhenItsTimeHasPassed() {
        let timetables = [line("764410", departing: 15 * 60)]

        guard case .board(_, let atFifteen) = WidgetContent.board(stopName: stop,
                                                                  timetables: timetables,
                                                                  now: TimeOfDay(minutes: 15 * 60)) else {
            return XCTFail("Expected a board")
        }
        guard case .board(_, let aMinuteLater) = WidgetContent.board(stopName: stop,
                                                                     timetables: timetables,
                                                                     now: TimeOfDay(minutes: 15 * 60 + 1)) else {
            return XCTFail("Expected a board")
        }
        guard case .board(_, let twoMinutesLater) = WidgetContent.board(stopName: stop,
                                                                        timetables: timetables,
                                                                        now: TimeOfDay(minutes: 15 * 60 + 2)) else {
            return XCTFail("Expected a board")
        }

        XCTAssertEqual(atFifteen.count, 1)
        // One minute of grace: the bus that has just left is still worth seeing,
        // because its expected time may be a minute behind the clock.
        XCTAssertEqual(aMinuteLater.count, 1)
        XCTAssertTrue(twoMinutesLater.isEmpty)
    }

    func testOnlyAsManyRowsAsTheFamilyHasRoomFor() {
        let timetables = (0..<6).map { line("76441\($0)", departing: 15 * 60 + $0 * 5, service: "\($0)") }

        guard case .board(_, let rows) = WidgetContent.board(stopName: stop,
                                                             timetables: timetables,
                                                             now: TimeOfDay(minutes: 15 * 60),
                                                             limit: 3) else {
            return XCTFail("Expected a board")
        }

        XCTAssertEqual(rows.count, 3)
    }

    func testALateVehicleKeepsItsDelayOnTheWidget() {
        let timetable = line("764410", departing: 15 * 60)

        guard case .board(_, let rows) = WidgetContent.board(stopName: stop,
                                                             timetables: [timetable],
                                                             lineDelays: [LineDelay(lineNumber: "764410",
                                                                                    minutes: 8,
                                                                                    destination: stop)],
                                                             now: TimeOfDay(minutes: 15 * 60)) else {
            return XCTFail("Expected a board")
        }

        XCTAssertEqual(rows.first?.delayMinutes, 8)
        XCTAssertEqual(rows.first?.expected?.text, "15:08")
    }

    // MARK: - What the stop picker offers

    /// A table the picker can be tested against: each stop with the lines that call
    /// at it, keyed the way the shipped file is.
    private func table(_ stops: [(name: String, lines: [String])]) -> StopPositions {
        var positions: [String: StopPosition] = [:]
        var lines: [String: [String]] = [:]
        for (index, stop) in stops.enumerated() {
            let key = StopPositions.lookupKey(for: stop.name)
            positions[key] = StopPosition(name: stop.name,
                                          latitude: 49.1 + Double(index) / 100,
                                          longitude: 15.4,
                                          match: .name,
                                          accuracyMetres: 20)
            lines[key] = stop.lines
        }
        return StopPositions(positions: positions, lines: lines)
    }

    func testThePickerStartsWithTheStarredStops() {
        let table = table([
            ("Telč,aut.nádr.", ["764410", "764420"]),
            ("Jihlava,aut.nádr.", ["764410"]),
            ("Třebíč,aut.nádr.", ["764420"])
        ])

        let suggested = WidgetContent.suggestedStops(in: table,
                                                     starred: StarredStops(["Třebíč,aut.nádr."]),
                                                     pinned: FavouriteLines(["420"]))

        XCTAssertEqual(suggested.first, "Třebíč,aut.nádr.")
    }

    func testThenTheStopsOfThePinnedLines() {
        let table = table([
            ("Telč,aut.nádr.", ["764410"]),
            ("Jihlava,aut.nádr.", ["764420"]),
            ("Třebíč,aut.nádr.", ["764420"])
        ])

        let suggested = WidgetContent.suggestedStops(in: table,
                                                     pinned: FavouriteLines(["420"]))

        XCTAssertEqual(suggested.prefix(2), ["Jihlava,aut.nádr.", "Třebíč,aut.nádr."])
    }

    func testAFreshInstallStillGetsAListToPickFrom() {
        let table = table([
            ("A", ["1"]),
            ("B", ["1", "2", "3"]),
            ("C", ["1", "2"])
        ])

        let suggested = WidgetContent.suggestedStops(in: table, limit: 2)

        // Busiest first, so the list is useful rather than alphabetical noise.
        XCTAssertEqual(suggested, ["B", "C"])
    }

    func testAStopNothingCallsAtIsNeverOffered() {
        let table = table([
            ("A", []),
            ("B", ["1"])
        ])

        XCTAssertEqual(WidgetContent.suggestedStops(in: table), ["B"])
    }

    func testTheListIsLimitedAndHasNoRepeats() {
        let table = table([
            ("A", ["1"]),
            ("B", ["1"]),
            ("C", ["1"])
        ])

        let suggested = WidgetContent.suggestedStops(in: table,
                                                     starred: StarredStops(["A"]),
                                                     pinned: FavouriteLines(["1"]),
                                                     limit: 2)

        XCTAssertEqual(suggested, ["A", "B"])
    }

    // MARK: - Where the traffic widget looks from

    private var table: StopPositions {
        StopPositions(
            positions: [StopPositions.lookupKey(for: stop): StopPosition(name: stop,
                                                                        latitude: 49.1842,
                                                                        longitude: 15.4528,
                                                                        match: .name,
                                                                        accuracyMetres: 20)],
            lines: [StopPositions.lookupKey(for: stop): ["764410"]]
        )
    }

    func testAChosenStopIsTheMiddleOfTheQuestion() {
        let origin = WidgetOrigin.resolve(stopNamed: stop,
                                          in: table,
                                          position: CLLocationCoordinate2D(latitude: 49.0, longitude: 15.0))

        XCTAssertEqual(origin.name, stop)
        XCTAssertEqual(origin.coordinate?.latitude ?? 0, 49.1842, accuracy: 0.000001)
    }

    func testWithNoStopTheLastPositionIsTheMiddle() {
        let position = CLLocationCoordinate2D(latitude: 49.0, longitude: 15.0)

        let origin = WidgetOrigin.resolve(stopNamed: nil, in: table, position: position)

        XCTAssertNil(origin.name)
        XCTAssertEqual(origin.coordinate?.latitude ?? 0, 49.0, accuracy: 0.000001)
    }

    func testAStopTheTableCannotPlaceIsNotAnOrigin() {
        let origin = WidgetOrigin.resolve(stopNamed: "Nikde,nic",
                                          in: table,
                                          position: CLLocationCoordinate2D(latitude: 49.0, longitude: 15.0))

        XCTAssertEqual(origin.name, "Nikde,nic")
        XCTAssertNil(origin.coordinate)
    }
}
