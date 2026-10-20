import CoreLocation
import XCTest
@testable import VdvLive

/// The rule that fills in the lines the feed has gone quiet about: which runs are
/// out at a moment, where they should be, and which of them the map may draw.
final class ExpectedServicesTests: XCTestCase {
    /// Prague, which is the calendar the timetables are published in.
    private let prague = ExpectedServices.regionTimeZone

    /// Two stops near Třešť, so a marker has somewhere to stand.
    private let positions = StopPositions(positions: [
        "trestnam": StopPosition(
            name: "Třešť,nám.",
            latitude: 49.29188,
            longitude: 15.48334,
            match: .name,
            accuracyMetres: 40
        ),
        "trestzastavka": StopPosition(
            name: "Třešť,zastávka",
            latitude: 49.29390,
            longitude: 15.48010,
            match: .name,
            accuracyMetres: 40
        ),
    ])

    // MARK: - Helpers

    private func moment(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = prague
        return calendar.date(from: DateComponents(
            year: 2026, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private func call(_ order: Int, _ stop: String, _ hour: Int, _ minute: Int) -> ScheduledCall {
        ScheduledCall(
            order: order,
            stopID: "\(order)",
            stopName: stop,
            arrival: nil,
            departure: TimeOfDay(minutes: hour * 60 + minute),
            distanceKilometres: nil,
            isServed: true
        )
    }

    private func timetable(
        _ lineNumber: String = "764337",
        runs: [ScheduledRun]
    ) -> LineTimetable {
        LineTimetable(
            lineNumber: lineNumber,
            displayNumber: LineCode(raw: lineNumber).number,
            routeName: "Třešť-Brtnice-Okříšky-Radonín",
            operatorName: nil,
            runs: runs
        )
    }

    private func morningRun(validity: [ValidityPeriod] = []) -> ScheduledRun {
        ScheduledRun(
            serviceNumber: "1",
            calls: [
                call(1, "Třešť,nám.", 4, 35),
                call(2, "Třešť,zastávka", 4, 41),
                call(3, "Třešť,nám.", 4, 52),
            ],
            validity: validity
        )
    }

    private func services(
        _ timetables: [LineTimetable],
        reporting: Set<String> = [],
        at now: Date
    ) -> [ExpectedService] {
        ExpectedServices.services(
            in: timetables,
            reportingLines: reporting,
            now: now,
            timeZone: prague,
            stopPositions: positions
        )
    }

    // MARK: - When a service is expected

    func testPlacesTheRunAtTheStopItIsDueAt() throws {
        let result = try XCTUnwrap(services([timetable(runs: [morningRun()])], at: moment(10, 20, 4, 39)).first)

        XCTAssertEqual(result.lineNumber, "764337")
        XCTAssertEqual(result.displayLine, "337")
        XCTAssertEqual(result.serviceNumber, "1")
        XCTAssertEqual(result.stopName, "Třešť,zastávka")
        XCTAssertEqual(result.scheduledTime, TimeOfDay(minutes: 4 * 60 + 41))
        XCTAssertEqual(result.latitude, 49.29390, accuracy: 0.00001)
        XCTAssertEqual(result.longitude, 15.48010, accuracy: 0.00001)
    }

    func testLeavesOutALineTheFeedIsReporting() {
        let result = services(
            [timetable(runs: [morningRun()])],
            reporting: ["764337"],
            at: moment(10, 20, 4, 38)
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testLeavesOutARunOutsideItsHours() {
        let result = services([timetable(runs: [morningRun()])], at: moment(10, 20, 11, 0))
        XCTAssertTrue(result.isEmpty)
    }

    func testKeepsARunJustAfterItsLastCallAndNotLongAfter() {
        // The last call is 04:52 and the slack is ten minutes.
        XCTAssertEqual(services([timetable(runs: [morningRun()])], at: moment(10, 20, 5, 0)).count, 1)
        XCTAssertTrue(services([timetable(runs: [morningRun()])], at: moment(10, 20, 5, 15)).isEmpty)
    }

    func testLeavesOutARunWhoseValidityDoesNotCoverToday() {
        let summer = ValidityPeriod(
            from: ServiceDay(archiveText: "01072026")!,
            to: ServiceDay(archiveText: "31082026")!
        )
        let result = services(
            [timetable(runs: [morningRun(validity: [summer])])],
            at: moment(10, 20, 4, 38)
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testKeepsARunInsideAnOpenValidityPeriod() {
        let open = ValidityPeriod(from: ServiceDay(archiveText: "02042026")!, to: nil)
        let result = services(
            [timetable(runs: [morningRun(validity: [open])])],
            at: moment(10, 20, 4, 38)
        )
        XCTAssertEqual(result.count, 1)
    }

    /// A night run is printed past midnight, so the minute now falls on has to be
    /// tried against the run's own day as well.
    func testFindsARunThatStartedBeforeMidnight() throws {
        let night = ScheduledRun(serviceNumber: "9", calls: [
            call(1, "Třešť,nám.", 23, 50),
            ScheduledCall(
                order: 2,
                stopID: "2",
                stopName: "Třešť,zastávka",
                arrival: nil,
                departure: TimeOfDay(minutes: 24 * 60 + 10),
                distanceKilometres: nil,
                isServed: true
            ),
        ])

        // 00:02 is nearer the 24:10 call than the 23:50 one, which is the whole
        // point: the run's own day is the one the minutes are measured on.
        let result = try XCTUnwrap(services([timetable(runs: [night])], at: moment(10, 21, 0, 2)).first)

        XCTAssertEqual(result.stopName, "Třešť,zastávka")
        XCTAssertEqual(result.scheduledTime, TimeOfDay(minutes: 24 * 60 + 10))
    }

    func testOneMarkerPerLinePicksTheRunNearestToNow() throws {
        let far = ScheduledRun(serviceNumber: "1", calls: [
            call(1, "Třešť,nám.", 4, 20),
            call(2, "Třešť,zastávka", 4, 30),
        ])
        let near = ScheduledRun(serviceNumber: "2", calls: [
            call(1, "Třešť,zastávka", 4, 36),
            call(2, "Třešť,nám.", 4, 50),
        ])

        let result = try XCTUnwrap(services([timetable(runs: [far, near])], at: moment(10, 20, 4, 40)).first)

        XCTAssertEqual(result.serviceNumber, "2")
        XCTAssertEqual(result.stopName, "Třešť,zastávka")
    }

    func testLeavesOutALineWhoseStopHasNoPosition() {
        let run = ScheduledRun(serviceNumber: "1", calls: [
            call(1, "Někde,nemáme", 4, 35),
            call(2, "Někde,jinde", 4, 45),
        ])
        // In its hours, but neither stop is in the shipped table: drawing one would
        // mean inventing a position.
        XCTAssertTrue(services([timetable(runs: [run])], at: moment(10, 20, 4, 40)).isEmpty)
    }

    func testLeavesOutALineWithNoTimetable() {
        XCTAssertTrue(services([], at: moment(10, 20, 4, 38)).isEmpty)
    }

    func testOrdersLinesTheWayTheyAreRead() {
        let line42 = timetable("764042", runs: [morningRun()])
        let line337 = timetable("764337", runs: [morningRun()])
        let result = services([line337, line42], at: moment(10, 20, 4, 38))

        XCTAssertEqual(result.map(\.displayLine), ["42", "337"])
    }

    // MARK: - Days

    func testReadsAnArchiveDate() throws {
        let day = try XCTUnwrap(ServiceDay(archiveText: "22122025"))
        XCTAssertEqual(day, try XCTUnwrap(ServiceDay(archiveText: "22122025")))
        XCTAssertLessThan(day, try XCTUnwrap(ServiceDay(archiveText: "31122025")))
    }

    func testRejectsAnArchiveDateThatIsNotADate() {
        for text in ["", "--", "2212202", "32122025", "22002025", "22.12.2025"] {
            XCTAssertNil(ServiceDay(archiveText: text), text)
        }
    }

    func testReadsTheDayInTheTimetableTimeZone() {
        // 00:30 in Prague on 21 October, which is still 20 October in UTC.
        let day = ServiceDay(date: moment(10, 21, 0, 30), in: prague)
        XCTAssertEqual(day, ServiceDay(archiveText: "21102026"))
    }
}
