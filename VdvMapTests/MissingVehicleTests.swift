import XCTest
@testable import VdvMap

/// The feed occasionally drops a vehicle for a payload or two. The map should
/// hold on to it - greyed out, where it was last seen - and only let it go once
/// it is clear the vehicle is gone.
@MainActor
final class MissingVehicleTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// Two vehicles in different grid cells.
    private var both: VehiclePayload {
        VehiclePayload(
            vehicles: [
                Fixture.vehicle(id: 1, latitude: 49.3960, longitude: 15.5910, traction: .bus),
                Fixture.vehicle(id: 2, latitude: 49.6070, longitude: 15.5810, traction: .train)
            ],
            skippedRecordCount: 0,
            unlocatableRecordCount: 0
        )
    }

    private var withoutSecond: VehiclePayload {
        VehiclePayload(
            vehicles: [Fixture.vehicle(id: 1, latitude: 49.3960, longitude: 15.5910, traction: .bus)],
            skippedRecordCount: 0,
            unlocatableRecordCount: 0
        )
    }

    private func makeViewModel(payloads: [VehiclePayload]) -> VehicleMapViewModel {
        let referenceDate = self.referenceDate
        return VehicleMapViewModel(
            fetcher: StubVehicleFetcher(payloads: payloads),
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(),
            markerMotionDuration: 0,
            now: { referenceDate }
        )
    }

    func testNothingIsStaleWhileEverythingReports() async {
        let viewModel = makeViewModel(payloads: [both])

        await viewModel.load()

        XCTAssertEqual(viewModel.clusters.count, 2)
        XCTAssertTrue(viewModel.clusters.allSatisfy { !$0.isStale })
        XCTAssertEqual(viewModel.vehicleCount, 2)
    }

    func testAVehicleThatGoesQuietStaysOnTheMapGreyedOut() async {
        let viewModel = makeViewModel(payloads: [both, withoutSecond])
        await viewModel.load()

        await viewModel.load()

        XCTAssertEqual(viewModel.clusters.count, 2, "it should still be there")
        let stale = viewModel.clusters.filter(\.isStale)
        XCTAssertEqual(stale.count, 1)
        XCTAssertEqual(stale.first?.singleVehicle?.id, 2)
        XCTAssertEqual(viewModel.vehicleCount, 1, "the header counts what is being reported")
        XCTAssertEqual(viewModel.visibleVehicleCount, 2)
    }

    func testItStaysForFourQuietLoadsAndGoesOnTheFifth() async {
        let viewModel = makeViewModel(payloads: [both, withoutSecond])
        await viewModel.load()

        for quiet in 1..<VehicleMapViewModel.missingLoadsBeforeRemoval {
            await viewModel.load()
            XCTAssertEqual(viewModel.clusters.count, 2, "quiet load \(quiet)")
        }

        // The fifth payload without news is where it leaves the map.
        await viewModel.load()
        XCTAssertEqual(viewModel.clusters.count, 1)
        XCTAssertEqual(viewModel.clusters.first?.singleVehicle?.id, 1)
    }

    func testAVehicleThatComesBackIsLiveAgain() async {
        let viewModel = makeViewModel(payloads: [both, withoutSecond, both])
        await viewModel.load()
        await viewModel.load()
        XCTAssertTrue(viewModel.clusters.contains { $0.isStale })

        await viewModel.load()

        XCTAssertEqual(viewModel.clusters.count, 2)
        XCTAssertTrue(viewModel.clusters.allSatisfy { !$0.isStale })
    }

    func testComingBackResetsTheCount() async {
        // Quiet, back, then quiet again: the second silence gets a full grace.
        let viewModel = makeViewModel(payloads: [both, withoutSecond, both, withoutSecond])
        await viewModel.load()
        await viewModel.load()
        await viewModel.load()

        for quiet in 1..<VehicleMapViewModel.missingLoadsBeforeRemoval {
            await viewModel.load()
            XCTAssertEqual(viewModel.clusters.count, 2, "quiet load \(quiet)")
        }

        await viewModel.load()
        XCTAssertEqual(viewModel.clusters.count, 1)
    }

    func testAFailedLoadDoesNotAgeAnything() async {
        // A network outage is not news about a vehicle, so the counter has to
        // stand still: three failures in among the quiet loads would otherwise
        // look like the vehicle being gone.
        let referenceDate = self.referenceDate
        let fetcher = StubVehicleFetcher(payloads: [both, withoutSecond])
        let viewModel = VehicleMapViewModel(
            fetcher: fetcher,
            favouriteLinesStore: InMemoryFavouriteLinesStore(),
            settingsStore: InMemoryAppSettingsStore(),
            languageDefaults: TestDefaults.make(),
            detailFetcher: StubVehicleDetailFetcher(),
            markerMotionDuration: 0,
            now: { referenceDate }
        )

        await viewModel.load()
        await viewModel.load()
        XCTAssertTrue(viewModel.clusters.contains { $0.isStale })

        fetcher.error = VehicleAPIError.transport("offline")
        for _ in 0..<3 {
            await viewModel.load()
        }
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.clusters.count, 2)

        // Four quiet payloads in total by now: one away from the limit, not seven.
        fetcher.error = nil
        for _ in 0..<3 {
            await viewModel.load()
            XCTAssertEqual(viewModel.clusters.count, 2)
        }
    }

    func testAStaleVehicleMergedWithALiveOneIsNotGrey() async {
        // Both in the same cell, then only the second reports.
        let together = VehiclePayload(
            vehicles: [
                Fixture.vehicle(id: 1, latitude: 49.3960, longitude: 15.5910, traction: .bus),
                Fixture.vehicle(id: 2, latitude: 49.3961, longitude: 15.5911, traction: .bus)
            ],
            skippedRecordCount: 0,
            unlocatableRecordCount: 0
        )
        let secondOnly = VehiclePayload(
            vehicles: [Fixture.vehicle(id: 2, latitude: 49.3961, longitude: 15.5911, traction: .bus)],
            skippedRecordCount: 0,
            unlocatableRecordCount: 0
        )
        let viewModel = makeViewModel(payloads: [together, secondOnly])
        await viewModel.load()

        await viewModel.load()

        let cluster = try? XCTUnwrap(viewModel.clusters.first)
        XCTAssertEqual(viewModel.clusters.count, 1)
        XCTAssertEqual(cluster?.count, 2)
        XCTAssertEqual(cluster?.isStale, false, "a grey marker carrying a live bus would be a lie")
    }

    func testAStaleVehicleStopsTheEmptyBanner() async {
        let viewModel = makeViewModel(payloads: [both, withoutSecond])
        await viewModel.load()
        viewModel.updateVisibleRegion(RegionOfInterest.vysocina.region)
        await viewModel.load()

        // Whatever is on screen, the held-on marker counts as something to show.
        XCTAssertGreaterThan(viewModel.visibleVehicleCount, 0)
    }
}
