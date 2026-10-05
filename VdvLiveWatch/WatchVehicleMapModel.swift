import Foundation
import Observation

/// What the watch map shows: the vehicles of the lines pinned on the phone.
///
/// Deliberately much smaller than the phone's map model. The watch has one screen
/// and no settings, so there is no filter to choose, no detail to fetch, no saved
/// view and no clustering - the pins come from the phone, the vehicles come from
/// the same public feed the phone uses, and a coloured dot per vehicle is all the
/// map draws.
@MainActor
@Observable
final class WatchVehicleMapModel {
    /// How often the feed is asked again while the map is on screen.
    ///
    /// Slower than the phone's fifteen seconds on purpose: a glance at the wrist
    /// does not need that resolution, and a watch pays for it in battery.
    static let refreshInterval: TimeInterval = 60

    private let fetcher: VehicleFetching
    private let favouritesSession: WatchFavouritesSession
    private var refreshTask: Task<Void, Never>?

    private(set) var vehicles: [Vehicle] = []
    private(set) var favouriteLines = FavouriteLines()
    private(set) var lastUpdatedAt: Date?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    nonisolated init(
        fetcher: VehicleFetching = VehicleAPIClient(),
        favouritesSession: WatchFavouritesSession = WatchFavouritesSession()
    ) {
        self.fetcher = fetcher
        self.favouritesSession = favouritesSession
    }

    /// Starts listening for the phone's pins, loads once, then keeps refreshing.
    func start() async {
        favouritesSession.onChange = { [weak self] in
            guard let self else { return }
            Task { await self.favouriteLinesChanged() }
        }
        favouritesSession.activate()
        favouriteLines = favouritesSession.favouriteLines
        await load()
        startAutoRefresh()
    }

    /// Fetches the feed and keeps only the pinned lines.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await fetcher.fetchVehicles()
            vehicles = payload.vehicles.filter { vehicle in
                vehicle.isLocatable && favouriteLines.contains(vehicle.line)
            }
            lastUpdatedAt = Date()
            errorMessage = nil
        } catch {
            // Whatever is already on the map stays: a missed refresh should not
            // blank a screen somebody is looking at.
            errorMessage = Self.message(for: error)
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func favouriteLinesChanged() async {
        favouriteLines = favouritesSession.favouriteLines
        await load()
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
                guard !Task.isCancelled else { return }
                await self?.load()
            }
        }
    }

    /// One short line, because it has to fit on a watch. The wording is the app's
    /// own, so the two screens do not describe the same failure differently.
    private static func message(for error: Error) -> String {
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut,
            .cannotFindHost, .cannotConnectToHost, .dataNotAllowed].contains(urlError.code) {
            return String(localized: "Offline")
        }
        return String(localized: "The vehicle feed could not be loaded.")
    }
}
