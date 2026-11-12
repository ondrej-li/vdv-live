import XCTest
@testable import VdvLive

/// Which publication a mapping belongs to, and which of a line's entries answers.
@MainActor
final class MappingFreshnessTests: XCTestCase {
    private let publication = ArchiveVersion(
        etag: "\"a5e723a1e72dd1:0\"",
        lastModified: Date(timeIntervalSince1970: 1_762_920_000),
        size: 106_229_789
    )

    private func mapping(etag: String? = nil,
                         lastModified: Date? = nil,
                         bytes: Int? = nil,
                         date: String? = "11112026") -> MappingArchive {
        MappingArchive(date: date, etag: etag, lastModified: lastModified, bytes: bytes)
    }

    func testAnEtagThatMatchesIsTheSamePublication() {
        XCTAssertEqual(MappingFreshness.between(mapping: mapping(etag: publication.etag), index: publication),
                       .current)
    }

    /// The case that broke every line at once: the mapping names entries of the
    /// archive that was published before the index on the phone.
    func testADifferentEtagMeansTheMappingIsStale() {
        XCTAssertEqual(MappingFreshness.between(mapping: mapping(etag: "\"a5e723a1e72dd1:-1\""),
                                                index: publication),
                       .stale(mapping: mapping(etag: "\"a5e723a1e72dd1:-1\""), index: publication))
    }

    func testASizeThatDiffersIsEnoughToKnowTheArchiveChanged() {
        XCTAssertTrue(MappingFreshness.between(mapping: mapping(bytes: 106_114_117),
                                               index: publication).isStale)
        XCTAssertEqual(MappingFreshness.between(mapping: mapping(bytes: publication.size),
                                                index: publication),
                       .current)
    }

    func testADateThatDiffersIsEnoughToKnowTheArchiveChanged() {
        let older = Date(timeIntervalSince1970: 1_762_000_000)
        XCTAssertTrue(MappingFreshness.between(mapping: mapping(lastModified: older),
                                               index: publication).isStale)
    }

    func testNothingComparableIsNeitherCurrentNorStale() {
        XCTAssertEqual(MappingFreshness.between(mapping: mapping(), index: publication), .unknown)
    }

    /// An ETag that matches settles it even when the server's date lags behind.
    func testAMatchingEtagOutranksADifferingDate() {
        XCTAssertEqual(
            MappingFreshness.between(
                mapping: mapping(etag: publication.etag, lastModified: Date(timeIntervalSince1970: 0)),
                index: publication
            ),
            .current
        )
    }

    // MARK: - Which of a line's entries answers

    private func timetable(from year: Int, month: Int, day: Int, service: String = "1") -> LineTimetable {
        LineTimetable(
            lineNumber: "766420",
            displayNumber: "420",
            routeName: "Jihlava-Třebíč",
            operatorName: nil,
            runs: [ScheduledRun(serviceNumber: service, calls: [
                ScheduledCall(order: 1,
                              stopID: "1",
                              stopName: "Jihlava,aut.nádr.",
                              arrival: nil,
                              departure: TimeOfDay(minutes: 8 * 60),
                              distanceKilometres: 0,
                              isServed: true)
            ])],
            validity: [ValidityPeriod(from: ServiceDay(year: year, month: month, day: day),
                                      to: ServiceDay(year: 2026, month: 12, day: 12))]
        )
    }

    /// A line is published once per validity period, and the one that took effect last
    /// is the one that applies - not whichever the mapping happened to list first.
    func testTheNewestPeriodThatHasStartedWins() {
        let older = LineTimetableStore.ResolvedEntry(
            timetable: timetable(from: 2025, month: 12, day: 14),
            entryName: "12965.zip",
            isFromEarlierArchive: false
        )
        let current = LineTimetableStore.ResolvedEntry(
            timetable: timetable(from: 2026, month: 10, day: 1),
            entryName: "11648.zip",
            isFromEarlierArchive: false
        )

        let chosen = LineTimetableStore.choose([older, current],
                                               serviceNumber: nil,
                                               today: ServiceDay(year: 2026, month: 11, day: 12))

        XCTAssertEqual(chosen?.entryName, "11648.zip")
    }

    /// A period that has not started yet is not the one to read today.
    func testAPeriodThatHasNotStartedYetDoesNotWin() {
        let current = LineTimetableStore.ResolvedEntry(
            timetable: timetable(from: 2026, month: 10, day: 1),
            entryName: "11648.zip",
            isFromEarlierArchive: false
        )
        let future = LineTimetableStore.ResolvedEntry(
            timetable: timetable(from: 2027, month: 1, day: 1),
            entryName: "99999.zip",
            isFromEarlierArchive: false
        )

        let chosen = LineTimetableStore.choose([current, future],
                                               serviceNumber: nil,
                                               today: ServiceDay(year: 2026, month: 11, day: 12))

        XCTAssertEqual(chosen?.entryName, "11648.zip")
    }

    /// The run the reader asked for decides first: two entries can carry the same
    /// line and only one of them has that `Spoj`.
    func testTheEntryHoldingTheRunAskedForWins() {
        let older = LineTimetableStore.ResolvedEntry(
            timetable: timetable(from: 2025, month: 12, day: 14, service: "1"),
            entryName: "12965.zip",
            isFromEarlierArchive: false
        )
        let newer = LineTimetableStore.ResolvedEntry(
            timetable: timetable(from: 2026, month: 10, day: 1, service: "2"),
            entryName: "11648.zip",
            isFromEarlierArchive: false
        )

        let chosen = LineTimetableStore.choose([older, newer],
                                               serviceNumber: "1",
                                               today: ServiceDay(year: 2026, month: 11, day: 12))

        XCTAssertEqual(chosen?.entryName, "12965.zip")
    }

    /// Everything else equal, the copy the current archive still holds is preferred
    /// to one read out of a file cached for an earlier publication.
    func testACurrentCopyBeatsACachedOlderOne() {
        let cached = LineTimetableStore.ResolvedEntry(
            timetable: timetable(from: 2026, month: 10, day: 1),
            entryName: "1.zip",
            isFromEarlierArchive: true
        )
        let current = LineTimetableStore.ResolvedEntry(
            timetable: timetable(from: 2026, month: 10, day: 1),
            entryName: "11648.zip",
            isFromEarlierArchive: false
        )

        let chosen = LineTimetableStore.choose([cached, current],
                                               serviceNumber: nil,
                                               today: ServiceDay(year: 2026, month: 11, day: 12))

        XCTAssertEqual(chosen?.entryName, "11648.zip")
    }
}
