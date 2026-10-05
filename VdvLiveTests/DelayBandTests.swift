import XCTest
@testable import VdvLive

final class DelayBandTests: XCTestCase {
    private func band(_ minutes: Int) -> DelayBand {
        DelayBand(VehicleDelay(rawMinutes: minutes))
    }

    /// The feed sends a sentinel for "no information". It must not read as on time,
    /// because a grey dot says nothing while a green one promises a bus is due.
    func testNoInformationIsItsOwnBand() {
        XCTAssertEqual(band(VehicleDelay.unknownSentinel), .unknown)
        XCTAssertEqual(DelayBand(.unknown), .unknown)
    }

    func testUpToFiveMinutesLateIsStillOnTime() {
        XCTAssertEqual(band(-3), .onTime)
        XCTAssertEqual(band(0), .onTime)
        XCTAssertEqual(band(1), .onTime)
        XCTAssertEqual(band(5), .onTime)
    }

    func testMoreThanFiveAndUpToTenMinutesIsLate() {
        XCTAssertEqual(band(6), .late)
        XCTAssertEqual(band(8), .late)
        XCTAssertEqual(band(10), .late)
    }

    func testMoreThanTenMinutesIsVeryLate() {
        XCTAssertEqual(band(11), .veryLate)
        XCTAssertEqual(band(45), .veryLate)
    }

    /// The bands partition the whole range, so no delay can fall between them.
    func testEveryDelayOfADayIsBanded() {
        let bands = Set((-20...120).map { DelayBand(VehicleDelay(rawMinutes: $0)) })

        XCTAssertEqual(bands, [.onTime, .late, .veryLate])
    }
}
