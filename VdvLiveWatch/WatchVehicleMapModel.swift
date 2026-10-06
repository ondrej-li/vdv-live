import CoreLocation
import Foundation
import Observation

/// What the watch map shows: the vehicles of the lines pinned on the phone.
///
/// Deliberately much smaller than the phone's map model. The watch has one screen
/// and no settings, so there is no filter to choose, no detail to fetch, no saved
/// view and no clustering - the pins come from the phone, the vehicles come from
/// the same public feed the phone uses, and a coloured dot per vehicle is all the
/// map draws.
///
/// It does keep one thing: the payload the feed last produced. A wrist is looked at
/// for a second, often somewhere without a network, and the positions from a few
/// minutes ago are a better answer than an empty map.
@MainActor
@Observable
final class WatchVehicleMapModel {
    /// How often the feed is asked again while the map is on screen.
    ///
    /// The phone's own default rather than a number of the watch's own: a marker
    /// that is a minute behind is indistinguishable from one that has stopped, and
    /// a wrist is read at a glance. What keeps this affordable is the screen rather
    /// than the interval - a watch sleeps within seconds of being lowered, and
    /// nothing here runs while the map is not in front of somebody.
    static let refreshInterval: TimeInterval = AppSettings.defaultAutoRefreshInterval

    /// How long the map has to have had a payload before it is written away.
    ///
    /// The file is read by one thing only - a launch that cannot reach the feed -
    /// so there is nothing to gain from rewriting it every minute, and a watch
    /// pays for every write.
    static let cacheSaveInterval: TimeInterval = 5 * 60

    private let fetcher: VehicleFetching
    private let favouritesSession: WatchFavouritesSession
    private let locationProvider: LocationProviding
    /// Where the last payload is kept between launches.
    private let payloadStore: VehiclePayloadStoring
    private var refreshTask: Task<Void, Never>?
    private var positionTask: Task<Void, Never>?

    private(set) var vehicles: [Vehicle] = []
    private(set) var favouriteLines = FavouriteLines()
    /// Where the wearer is, once there is a fix. Drawn as a dot by the map.
    private(set) var userCoordinate: CLLocationCoordinate2D?
    private(set) var lastUpdatedAt: Date?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Everything the feed last said, whole rather than already filtered, so that
    /// a line pinned in the meantime can be drawn from it without a fetch.
    private var lastPayload: VehiclePayload?
    private var lastSavedAt: Date?

    nonisolated init(
        fetcher: VehicleFetching = VehicleAPIClient(),
        favouritesSession: WatchFavouritesSession = WatchFavouritesSession(),
        locationProvider: LocationProviding = SystemLocationProvider(),
        payloadStore: VehiclePayloadStoring = VehiclePayloadFiles()
    ) {
        self.fetcher = fetcher
        self.favouritesSession = favouritesSession
        self.locationProvider = locationProvider
        self.payloadStore = payloadStore
    }

    /// Starts listening for the phone's pins, loads once, then keeps refreshing.
    func start() async {
        favouritesSession.onChange = { [weak self] in
            guard let self else { return }
            Task { await self.favouriteLinesChanged() }
        }
        favouritesSession.activate()
        favouriteLines = favouritesSession.favouriteLines
        // What an earlier launch left behind goes on the map before the network is
        // asked anything: an empty screen for as long as a fetch takes is worse
        // than positions a few minutes old.
        showStoredPayload()
        await load()
        startAutoRefresh()
        // Started after the first load, so the vehicles are on screen while the
        // permission prompt is being read. The stream is what asks: it reports a
        // refusal, and a position once there is one.
        startFollowingPosition()
    }

    /// Fetches the feed and keeps only the pinned lines.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await fetcher.fetchVehicles()
            let fetchedAt = Date()
            lastPayload = payload
            lastUpdatedAt = fetchedAt
            showVehicles(in: payload)
            errorMessage = nil
            savePayloadIfStaleEnough(fetchedAt)
        } catch {
            // Whatever is already on the map stays: a missed refresh should not
            // blank a screen somebody is looking at.
            errorMessage = Self.message(for: error)
        }
    }

    /// Everything that should stop when the map goes away: the refresh timer and
    /// the position, both of which cost battery while they run.
    func stop() {
        // Whatever arrived this session is the freshest thing the next launch could
        // start from, so it goes away with it.
        savePayload()
        refreshTask?.cancel()
        refreshTask = nil
        positionTask?.cancel()
        positionTask = nil
    }

    private func favouriteLinesChanged() async {
        favouriteLines = favouritesSession.favouriteLines
        // Redrawn from the payload already in hand, so a line pinned while the
        // watch could not reach the feed appears straight away; the fetch that
        // follows then corrects the positions.
        showVehicles(in: lastPayload)
        await load()
    }

    /// Puts the vehicles of the pinned lines on the map, out of a payload.
    private func showVehicles(in payload: VehiclePayload?) {
        vehicles = payload?.vehicles(onPinnedLines: favouriteLines) ?? []
    }

    /// Shows what an earlier launch kept, if it kept anything.
    private func showStoredPayload() {
        guard let stored = payloadStore.load() else { return }
        lastPayload = stored.payload
        lastUpdatedAt = stored.fetchedAt
        showVehicles(in: stored.payload)
    }

    /// Keeps what was fetched for the next launch.
    private func savePayload() {
        guard let lastPayload, let lastUpdatedAt else { return }
        payloadStore.save(lastPayload, fetchedAt: lastUpdatedAt)
        lastSavedAt = lastUpdatedAt
    }

    /// Keeps it, unless it was written recently enough.
    private func savePayloadIfStaleEnough(_ fetchedAt: Date) {
        if let lastSavedAt, fetchedAt.timeIntervalSince(lastSavedAt) < Self.cacheSaveInterval {
            return
        }
        savePayload()
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

    private func startFollowingPosition() {
        positionTask?.cancel()
        positionTask = Task { [weak self] in
            guard let provider = self?.locationProvider else { return }
            for await coordinate in provider.positions() {
                guard !Task.isCancelled else { return }
                self?.userCoordinate = coordinate
            }
        }
    }

    /// One short line, because it has to fit on a watch. The wording is the app's
    /// own, so the two screens do not describe the same failure differently.
    private static func message(for error: Error) -> String {
        if isUnreachable(error) {
            return String(localized: "Offline")
        }
        return String(localized: "The vehicle feed could not be loaded.")
    }

    /// Whether the feed never answered, as opposed to answering with something the
    /// app could not read.
    ///
    /// The client wraps every transport failure, so the rule has to be asked of the
    /// error itself; a bare `URLError` is still possible from anything that dials
    /// out without the client, and means the same thing.
    private static func isUnreachable(_ error: Error) -> Bool {
        if (error as? VehicleAPIError)?.isFeedUnreachable == true { return true }
        guard let urlError = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                .cannotFindHost, .cannotConnectToHost, .dataNotAllowed].contains(urlError.code)
    }
}
