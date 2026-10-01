import XCTest
@testable import VdvLive

/// Parses the fixture taken from the official export: line 764337, the pinned
/// line 337, whose archive entry is `8354.zip` in the current publication.
final class JDFTimetableParserTests: XCTestCase {
    private func lineFiles() throws -> [String: Data] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "jdf-line-764337", withExtension: "zip"))
        let archive = try Data(contentsOf: url)
        return try ZipArchive.entries(in: archive)
            .reduce(into: [String: Data]()) { files, entry in
                files[entry.name] = try? ZipArchive.contents(of: entry, in: archive)
            }
    }

    func testReadsTheLine() throws {
        let timetable = try JDFTimetableParser.parse(files: try lineFiles())

        XCTAssertEqual(timetable.lineNumber, "764337")
        XCTAssertEqual(timetable.displayNumber, "337")
        XCTAssertEqual(timetable.routeName, "Třešť-Brtnice-Okříšky-Radonín")
        XCTAssertEqual(timetable.operatorName, "ČSAD AUTOBUSY České Budějovice a.s.")
        XCTAssertFalse(timetable.isEmpty)
    }

    func testReadsRunsAndCallsInOrder() throws {
        let timetable = try JDFTimetableParser.parse(files: try lineFiles())
        let run = try XCTUnwrap(timetable.run(serviceNumber: "1"))

        XCTAssertEqual(run.calls.count, 8)
        XCTAssertEqual(run.calls.map(\.order), run.calls.map(\.order).sorted())
        XCTAssertEqual(run.calls.first?.order, 1)

        // Run 1 leaves Třešť at 04:35 according to the archive.
        let first = try XCTUnwrap(run.calls.first)
        XCTAssertEqual(first.stopName, "Třešť,nám.")
        XCTAssertEqual(first.time, TimeOfDay(minutes: 4 * 60 + 35))
        XCTAssertEqual(first.time?.text, "04:35")
        XCTAssertEqual(first.distanceKilometres, 0)
        XCTAssertFalse(first.isOnRequest)
    }

    func testEveryCallEitherHasATimeOrIsOnRequest() throws {
        let timetable = try JDFTimetableParser.parse(files: try lineFiles())

        for run in timetable.runs {
            XCTAssertFalse(run.calls.isEmpty, "run \(run.serviceNumber)")
            for call in run.calls {
                XCTAssertFalse(call.stopName.isEmpty, "run \(run.serviceNumber) call \(call.order)")
                XCTAssertTrue(
                    call.hasTime || call.isOnRequest,
                    "run \(run.serviceNumber) call \(call.order) has neither"
                )
            }
        }
    }

    func testRequestStopsCarryNoTime() throws {
        let timetable = try JDFTimetableParser.parse(files: try lineFiles())
        let run = try XCTUnwrap(timetable.run(serviceNumber: "13"))
        let call = try XCTUnwrap(run.calls.first { $0.order == 16 })

        // The archive writes `<` in the time columns for a stop served only on
        // request, which means there is no time to quote - not a broken row.
        XCTAssertTrue(call.isOnRequest)
        XCTAssertNil(call.time)
        XCTAssertEqual(call.stopName, "Petrovice")
    }

    func testTimesIncreaseAlongARun() throws {
        let timetable = try JDFTimetableParser.parse(files: try lineFiles())
        let run = try XCTUnwrap(timetable.run(serviceNumber: "1"))

        // A run that serves every stop on request is skipped: with no quoted
        // times there is nothing to compare.
        let times = run.calls.compactMap(\.time)
        XCTAssertEqual(times.count, run.calls.count)
        XCTAssertEqual(times, times.sorted())
    }

    func testArrivalOrDepartureIsEnough() throws {
        let timetable = try JDFTimetableParser.parse(files: try lineFiles())
        let run = try XCTUnwrap(timetable.run(serviceNumber: "1"))

        // The archive fills in one of the two columns at most: the departure
        // along the way, the arrival at the end of the line.
        XCTAssertTrue(run.calls.allSatisfy { $0.arrival == nil || $0.departure == nil })
        XCTAssertNotNil(run.lastCall?.arrival)
    }

    func testDelayShiftsEveryCall() throws {
        let timetable = try JDFTimetableParser.parse(files: try lineFiles())
        let run = try XCTUnwrap(timetable.run(serviceNumber: "1"))
        let first = try XCTUnwrap(run.calls.first)

        XCTAssertEqual(first.time(lateByMinutes: 7)?.text, "04:42")
        XCTAssertEqual(first.time(lateByMinutes: -5)?.text, "04:30")
    }

    func testFindsTheRunOfAVehicleFromTheInfoWindow() throws {
        let timetable = try JDFTimetableParser.parse(files: try lineFiles())

        XCTAssertNotNil(timetable.run(serviceNumber: Optional("1")))
        XCTAssertNil(timetable.run(serviceNumber: Optional("999")))
        XCTAssertNil(timetable.run(serviceNumber: nil))
    }

    func testFindsTheCallOfAReportedStop() throws {
        let timetable = try JDFTimetableParser.parse(files: try lineFiles())

        // The feed writes the same stop with different case and spacing.
        let call = try XCTUnwrap(timetable.call(matchingStopName: "třešť , nám."))

        XCTAssertEqual(call.stopName, "Třešť,nám.")
    }

    func testStopNamesIgnoreDistrictSuffixes() {
        XCTAssertEqual(
            LineTimetable.comparableStopName("Brtnice [JI],Horní město"),
            LineTimetable.comparableStopName("Brtnice,Horní město")
        )
        XCTAssertEqual(
            LineTimetable.comparableStopName("Telč,aut.nádr."),
            LineTimetable.comparableStopName("  TELC , AUT.NADR. ")
        )
    }
    func testRefusesAPackageWithoutCalls() throws {
        XCTAssertThrowsError(try JDFTimetableParser.parse(files: [:])) { error in
            XCTAssertEqual(error as? JDFTimetableParser.Failure, .missingFile("Zasspoje.txt"))
        }
    }

    func testWorksWithoutTheOptionalTables() throws {
        var files = try lineFiles()
        files["Linky.txt"] = nil
        files["Dopravci.txt"] = nil
        files["Zastavky.txt"] = nil

        let timetable = try JDFTimetableParser.parse(files: files)

        XCTAssertEqual(timetable.lineNumber, "764337")
        XCTAssertNil(timetable.operatorName)
        XCTAssertFalse(timetable.runs.isEmpty)
        // Without the stop table the runs survive, just without names.
        XCTAssertEqual(timetable.runs.first?.calls.first?.stopName, "")
    }

    // MARK: - Time of day

    func testParsesClockStrings() {
        XCTAssertEqual(TimeOfDay(clock: "0435")?.minutes, 4 * 60 + 35)
        XCTAssertEqual(TimeOfDay(clock: "2359")?.minutes, 23 * 60 + 59)
        XCTAssertNil(TimeOfDay(clock: ""))
        XCTAssertNil(TimeOfDay(clock: "--"))
        XCTAssertNil(TimeOfDay(clock: "9999"))
        XCTAssertNil(TimeOfDay(clock: "123"))
    }

    func testFormatsTimesPastMidnight() {
        XCTAssertEqual(TimeOfDay(minutes: 5 * 60).text, "05:00")
        XCTAssertEqual(TimeOfDay(minutes: 24 * 60 + 35).text, "00:35")
    }
}
