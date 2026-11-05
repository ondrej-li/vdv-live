import XCTest
@testable import VdvLive

/// What a share says, and what happens when somebody taps the link in it.
final class ShareComposerTests: XCTestCase {
    private func entry(line: String, destination: String?, scheduled: Int, expected: Int?) -> StopBoardEntry {
        StopBoardEntry(lineNumber: line,
                       serviceNumber: "1",
                       scheduled: TimeOfDay(minutes: scheduled),
                       expected: expected.map(TimeOfDay.init(minutes:)),
                       destination: destination)
    }

    // MARK: - A vehicle

    func testAVehicleShareSaysWhereItIsGoingAndHowLateItIs() {
        let share = ShareComposer.vehicle(line: "764337",
                                          destination: "Jihlava,aut.nádr.",
                                          delayMinutes: 3,
                                          observedAt: nil,
                                          lastStop: "Telč,aut.nádr.",
                                          nextStop: "Telč,rozc.",
                                          serviceNumber: "3")

        // The words come from the catalogue, so these assert the facts of the
        // message rather than one of its translations.
        XCTAssertTrue(share.title.contains("337"), share.title)
        XCTAssertTrue(share.body.hasPrefix("337 → Jihlava, aut.nádr."), share.body)
        XCTAssertTrue(share.body.contains("+3 min"), share.body)
        XCTAssertTrue(share.body.contains("Telč, aut.nádr."), share.body)
        XCTAssertTrue(share.body.contains("Telč, rozc."), share.body)
    }

    func testANonReportingVehicleSaysTheDelayIsUnknownRatherThanOnTime() {
        let share = ShareComposer.vehicle(line: "764337",
                                          destination: "Jihlava,aut.nádr.",
                                          delayMinutes: nil,
                                          observedAt: nil,
                                          lastStop: nil,
                                          nextStop: nil,
                                          serviceNumber: nil)

        XCTAssertTrue(share.body.contains(VehicleDelay.unknown.displayText), share.body)
        XCTAssertFalse(share.body.contains(VehicleDelay.minutes(0).displayText), share.body)
    }

    func testTheShareCarriesTheLinkAndNotTheLinkAndTheText() {
        let share = ShareComposer.vehicle(line: "764337",
                                          destination: nil,
                                          delayMinutes: 0,
                                          observedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                          lastStop: nil,
                                          nextStop: nil,
                                          serviceNumber: "3")

        XCTAssertEqual(share.url.absoluteString,
                       "https://vdv.ondralinek.cz/s/?line=337&service=3")
    }

    // MARK: - A board

    func testABoardShareCarriesFiveDepartures() {
        let rows = (0..<8).map { index in
            entry(line: "76441\(index)", destination: "Jihlava", scheduled: 900 + index * 5, expected: nil)
        }

        let share = ShareComposer.board(stopName: "Telč,aut.nádr.", rows: rows, readAt: Date())

        XCTAssertEqual(share.body.split(separator: "\n").count, 6, share.body)  // header + five
        XCTAssertTrue(share.body.contains("15:00"), share.body)
        XCTAssertTrue(share.body.contains("15:20"), share.body)
        XCTAssertFalse(share.body.contains("15:25"), share.body)
    }

    func testABoardShareSpellsOutTheStatusOfEachRow() {
        let rows = [
            entry(line: "764410", destination: "Jihlava", scheduled: 900, expected: 903),
            entry(line: "764420", destination: "Třebíč", scheduled: 910, expected: 910),
            entry(line: "764430", destination: "Telč", scheduled: 920, expected: nil)
        ]

        let share = ShareComposer.board(stopName: "Telč,aut.nádr.", rows: rows, readAt: Date())

        XCTAssertTrue(share.body.contains("(+3 min)"), share.body)
        XCTAssertTrue(share.body.contains("(\(VehicleDelay.minutes(0).displayText))"), share.body)
        XCTAssertTrue(share.body.contains("(\(String(localized: "scheduled")))"), share.body)
    }

    // MARK: - Links

    func testABoardLinkRoundTripsThroughItsOwnParser() {
        let url = ShareComposer.boardURL(stopName: "Telč,aut.nádr.")

        XCTAssertEqual(ShareComposer.target(from: url), .board(stopName: "Telč,aut.nádr."))
    }

    func testAVehicleLinkRoundTripsThroughItsOwnParser() {
        let url = ShareComposer.vehicleURL(line: "764337", serviceNumber: "3")

        XCTAssertEqual(ShareComposer.target(from: url), .vehicle(line: "337", serviceNumber: "3"))
    }

    func testALinkWithoutAServiceStillNamesTheLine() {
        let url = ShareComposer.vehicleURL(line: "337", serviceNumber: nil)

        XCTAssertEqual(ShareComposer.target(from: url), .vehicle(line: "337", serviceNumber: nil))
    }

    func testLinksToAnythingElseAreNotOpened() {
        XCTAssertNil(ShareComposer.target(from: URL(string: "https://vdv.ondralinek.cz/")!))
        XCTAssertNil(ShareComposer.target(from: URL(string: "https://example.com/s/?stop=X")!))
        XCTAssertNil(ShareComposer.target(from: URL(string: "https://vdv.ondralinek.cz/s/")!))
    }
}
