import Foundation
import MapKit
import Observation

/// Owns the vehicle data shown on the map.
///
/// Everything here runs on the main actor: the view model is only a thin layer
/// that turns one payload into the markers of the current viewport.
@MainActor
@Observable
final class VehicleMapViewModel {
    /// Markers for the visible region, ordered so SwiftUI can diff them. Each one
    /// carries the position it is drawn at, which the map reads.
    private(set) var clusters: [VehicleCluster] = []
    /// Vehicles matching the current filter, on screen or not.
    private(set) var vehicleCount = 0
    /// Vehicles that made it into ``clusters``.
    private(set) var visibleVehicleCount = 0
    private(set) var lastUpdatedAt: Date?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    /// Tractions present in the latest payload, in menu order.
    private(set) var availableTractions: [Traction] = []
    /// What the map is showing.
    private(set) var filter: VehicleFilter = .all
    /// Lines the user pinned, kept in sync with the store.
    private(set) var favouriteLines: FavouriteLines = FavouriteLines()
    /// Markers that contain at least one vehicle on a pinned line, so the map
    /// can decorate them without walking every cluster while drawing.
    private(set) var favouriteClusterIDs: Set<String> = []
    /// Every line reporting right now, busiest first.
    private(set) var runningLines: [LineSummary] = []
    /// Detail popup of the selected vehicle, once it has been fetched.
    private(set) var vehicleDetail: VehicleDetail?
    /// True while the detail popup of the selected vehicle is being fetched.
    private(set) var isLoadingDetail = false
    /// Published timetable of the selected vehicle's line, when the user has
    /// downloaded the timetable index.
    private(set) var lineTimetable: LineTimetable?
    private(set) var isLoadingTimetable = false
    private(set) var timetableError: String?
    /// Latitude span the map currently shows, used for the scale legend.
    private(set) var visibleLatitudeDelta: CLLocationDegrees =
        RegionOfInterest.vysocina.region.span.latitudeDelta
    /// Choices made on the settings screen, kept in sync with the store.
    private(set) var settings: AppSettings

    /// Marker the user tapped; owned by the view through a binding.
    var selectedClusterID: String?

    private let fetcher: VehicleFetching
    private let favouriteLinesStore: FavouriteLinesPersisting
    private let settingsStore: AppSettingsStoring
    private let locationProvider: LocationProviding
    /// Defaults the language override is written to; injected so that tests do
    /// not change the language of the app they run inside.
    private let languageDefaults: UserDefaults
    private let detailFetcher: VehicleDetailFetching
    private let clusterer: VehicleGridClusterer
    /// Official timetables, shared with the settings screen that downloads them.
    let timetables: LineTimetableStore
    /// How long a marker takes to travel to its new position.
    private let markerMotionDuration: TimeInterval
    /// Frames per second used while markers travel.
    private let markerMotionFrameRate: Double
    private var vehicles: [Vehicle] = []
    private var grid: VehicleGrid?
    /// Viewport the map is showing, so that the lock button can remember exactly
    /// what is on screen rather than guessing from the zoom level alone.
    private var visibleRegion: MKCoordinateRegion = RegionOfInterest.vysocina.region
    private var autoRefreshTask: Task<Void, Never>?
    private var markerMotionTask: Task<Void, Never>?
    private let now: () -> Date
    /// Vehicle the in-flight detail request belongs to, so that a slow response
    /// for a previously selected marker cannot overwrite a newer one.
    private var detailRequestVehicleID: Int?

    init(
        fetcher: VehicleFetching,
        favouriteLinesStore: FavouriteLinesPersisting = UserDefaultsFavouriteLinesStore(),
        settingsStore: AppSettingsStoring = UserDefaultsAppSettingsStore(),
        locationProvider: LocationProviding = SystemLocationProvider(),
        languageDefaults: UserDefaults = .standard,
        detailFetcher: VehicleDetailFetching = VehicleDetailClient(),
        clusterer: VehicleGridClusterer = VehicleGridClusterer(),
        timetables: LineTimetableStore? = nil,
        markerMotionDuration: TimeInterval = 2,
        markerMotionFrameRate: Double = 30,
        now: @escaping () -> Date = Date.init
    ) {
        self.fetcher = fetcher
        self.favouriteLinesStore = favouriteLinesStore
        self.settingsStore = settingsStore
        self.locationProvider = locationProvider
        self.languageDefaults = languageDefaults
        self.detailFetcher = detailFetcher
        self.clusterer = clusterer
        self.timetables = timetables ?? LineTimetableStore()
        self.markerMotionDuration = markerMotionDuration
        self.markerMotionFrameRate = markerMotionFrameRate
        self.now = now
        // Whatever the store hands over is used as is: `UserDefaultsAppSettingsStore`
        // has already applied the minimum interval to what it read from disk.
        self.settings = settingsStore.load()
        self.favouriteLines = favouriteLinesStore.load()
        // Restore the quiet map straight away, so that a user who only wants
        // their own lines does not have to filter again on every launch.
        self.filter = favouriteLinesStore.loadShowsOnlyFavourites() ? .favourites : .all
        restartAutoRefreshTask()
    }

    var hasLoadedOnce: Bool { lastUpdatedAt != nil }

    var isAutoRefreshEnabled: Bool { settings.autoRefreshEnabled }

    /// Seconds between automatic refreshes.
    var autoRefreshInterval: TimeInterval { settings.autoRefreshInterval }

    /// Filter chips shown above the map: everything, the pinned lines, then the
    /// tractions that are actually running.
    var availableFilters: [VehicleFilter] {
        [.all, .favourites] + availableTractions.map(VehicleFilter.traction)
    }

    var selectedCluster: VehicleCluster? {
        guard let selectedClusterID else { return nil }
        return clusters.first { $0.id == selectedClusterID }
    }

    /// Loads the first payload, once.
    func loadIfNeeded() async {
        guard !hasLoadedOnce, !isRefreshing else { return }
        await load()
    }

    /// Fetches the current positions. Keeps the previous payload on failure so
    /// the map does not go blank while the network is down.
    func load() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let payload = try await fetcher.fetchVehicles()
            let previous = vehicles
            vehicles = payload.vehicles
            lastUpdatedAt = now()
            errorMessage = nil
            trackMissing(from: previous)
            // What is on the map, greyed vehicles included: a traction that is
            // only quiet for a payload should not make its chip vanish.
            availableTractions = Self.tractions(in: trackedVehicles())
            runningLines = Self.runningLines(in: vehicles)
            if case .traction(let traction) = filter, !availableTractions.contains(traction) {
                filter = .all
            }
            rebuildClusters()
        } catch {
            // A failed load is not news about any vehicle, so nothing ages.
            errorMessage = Self.message(for: error)
        }
    }

    /// Vehicles the feed is reporting, plus the ones still being held on to.
    private func trackedVehicles() -> [Vehicle] {
        vehicles + missingVehicles.values.map(\.vehicle)
    }

    /// Notes which vehicles the latest payload left out.
    ///
    /// The feed drops a vehicle for a payload or two and then reports it again,
    /// so a vehicle that has gone quiet is kept on the map - greyed out, where it
    /// was last seen - until it has been missing for
    /// ``missingLoadsBeforeRemoval`` payloads in a row.
    private func trackMissing(from previous: [Vehicle]) {
        let current = Set(vehicles.map(\.id))
        var updated: [Int: MissingVehicle] = [:]

        for (id, entry) in missingVehicles where !current.contains(id) {
            let loads = entry.loads + 1
            guard loads < Self.missingLoadsBeforeRemoval else { continue }
            updated[id] = MissingVehicle(vehicle: entry.vehicle, loads: loads)
        }

        // Vehicles that were reporting last time and are not now.
        for vehicle in previous where !current.contains(vehicle.id) {
            guard updated[vehicle.id] == nil else { continue }
            updated[vehicle.id] = MissingVehicle(vehicle: vehicle, loads: 1)
        }

        missingVehicles = updated
    }

    /// Called when the map settles after a pan or a zoom.
    func updateVisibleRegion(_ region: MKCoordinateRegion) {
        // Kept whole, not just as a span: the lock button saves the viewport the
        // user is looking at, which is a centre as well as a zoom level.
        visibleRegion = region
        // Kept before the grid check: the legend needs the new zoom level even
        // when the markers end up grouped exactly as they were.
        visibleLatitudeDelta = region.span.latitudeDelta

        let newGrid = clusterer.grid(for: region)
        guard newGrid != grid else { return }
        grid = newGrid
        rebuildClusters()
    }

    func select(filter: VehicleFilter) {
        guard self.filter != filter else { return }
        self.filter = filter
        // Only the pinned filter is worth remembering: a traction filter goes
        // stale as soon as that traction stops running.
        favouriteLinesStore.saveShowsOnlyFavourites(filter == .favourites)
        rebuildClusters()
    }

    /// Whether the map is showing pinned lines only.
    var showsOnlyPinnedLines: Bool { filter == .favourites }

    func setShowsOnlyPinnedLines(_ showsOnlyPinnedLines: Bool) {
        select(filter: showsOnlyPinnedLines ? .favourites : .all)
    }

    // MARK: - Selected vehicle detail

    /// Called when the user selects or deselects a marker.
    ///
    /// The detail popup costs two requests, so it is only fetched for a marker
    /// that stands for a single vehicle: picking one of twenty buses parked in
    /// the same cell would be arbitrary.
    func selectionDidChange() async {
        guard let vehicle = selectedCluster?.singleVehicle else {
            clearVehicleDetail()
            return
        }
        await loadDetail(for: vehicle)
    }

    func loadDetail(for vehicle: Vehicle) async {
        detailRequestVehicleID = vehicle.id
        vehicleDetail = nil
        clearTimetable()
        isLoadingDetail = true
        defer {
            if detailRequestVehicleID == vehicle.id {
                isLoadingDetail = false
            }
        }

        do {
            let detail = try await detailFetcher.fetchDetail(for: vehicle)
            guard detailRequestVehicleID == vehicle.id else { return }
            vehicleDetail = detail
            await loadTimetable(forLine: detail.lineCode.fullText, serviceNumber: detail.serviceNumber)
        } catch {
            // Nothing to say: the card falls back to what the points feed
            // already told us about the vehicle.
            guard detailRequestVehicleID == vehicle.id else { return }
            vehicleDetail = nil
        }
    }

    /// Looks the run up in the official timetable.
    ///
    /// Only worth doing once the user has downloaded the index; until then the
    /// card shows what the feed's own detail endpoint gave it.
    func loadTimetable(forLine lineNumber: String, serviceNumber: String?) async {
        guard timetables.isReady else { return }
        isLoadingTimetable = true
        defer { isLoadingTimetable = false }

        do {
            lineTimetable = try await timetables.timetable(
                forLine: lineNumber,
                serviceNumber: serviceNumber
            )
            timetableError = nil
        } catch {
            lineTimetable = nil
            timetableError = (error as? TimetableError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Picks the timetable up again for whatever is on screen, which is what the
    /// settings screen asks for once the index has been downloaded.
    func reloadTimetableForSelection() async {
        guard let detail = vehicleDetail else { return }
        await loadTimetable(forLine: detail.lineCode.fullText, serviceNumber: detail.serviceNumber)
    }

    /// Drops everything the timetable store had, including the entries cached on
    /// disk.
    func forgetTimetables() {
        timetables.forgetIndex()
        clearTimetable()
    }

    private func clearTimetable() {
        lineTimetable = nil
        timetableError = nil
        isLoadingTimetable = false
    }

    func clearVehicleDetail() {
        detailRequestVehicleID = nil
        vehicleDetail = nil
        isLoadingDetail = false
        clearTimetable()
    }

    // MARK: - Pinned lines

    func isFavourite(line: String) -> Bool {
        favouriteLines.contains(line)
    }

    /// Whether a vehicle runs on the given line.
    ///
    /// Pins are held as line numbers (`337`) while the feed sends operator
    /// prefixed codes (`764337`), so the comparison goes through ``LineCode``.
    func vehicle(_ vehicle: Vehicle, isOn line: String) -> Bool {
        favouriteLines.contains(vehicle.line) || favouriteLines.contains(line)
    }

    /// Pins the line when it was not pinned, unpins it otherwise.
    func toggleFavourite(line: String) {
        var updated = favouriteLines
        updated.toggle(line)
        setFavouriteLines(updated)
    }

    func pin(line: String) {
        var updated = favouriteLines
        updated.pin(line)
        setFavouriteLines(updated)
    }

    func unpin(line: String) {
        var updated = favouriteLines
        updated.unpin(line)
        setFavouriteLines(updated)
    }

    /// Summary of an arbitrary line code, so pinned lines that are not running
    /// can still be listed.
    func summary(forLine line: String) -> LineSummary {
        let normalized = FavouriteLines.normalize(line)
        return runningLines.first { $0.line == normalized } ?? .idle(normalized)
    }

    /// First vehicle reporting on `line`, used to fly the map to a pinned line.
    func firstVehicle(forLine line: String) -> Vehicle? {
        let wanted = FavouriteLines.normalize(line)
        return vehicles.first { FavouriteLines.normalize($0.line) == wanted }
    }

    /// First pinned line that is running, used to offer a jump to it when the
    /// map is filtered down to pinned lines but none of them are in view.
    var firstRunningPinnedLine: String? {
        favouriteLines.orderedForDisplay.first { summary(forLine: $0).isRunning }
    }

    private func setFavouriteLines(_ lines: FavouriteLines) {
        guard lines != favouriteLines else { return }
        favouriteLines = lines
        favouriteLinesStore.save(lines)
        rebuildClusters()
    }

    // MARK: - Where the map opens

    /// Region the map opens on before any position is known: the viewport the
    /// user locked, otherwise the whole region.
    var launchRegion: MKCoordinateRegion {
        settings.savedMapView?.region ?? RegionOfInterest.vysocina.region
    }

    var savedMapView: SavedMapView? { settings.savedMapView }

    var startsAtCurrentLocation: Bool { settings.startsAtCurrentLocation }

    /// Region around the user, for a map that should open there.
    ///
    /// Returns `nil` when the question is already answered or cannot be: a locked
    /// viewport outranks the current location, the option can be switched off,
    /// the position may be unavailable, and a position outside the region the
    /// feed covers would only produce an empty map.
    func currentLocationRegion() async -> MKCoordinateRegion? {
        guard settings.savedMapView == nil, settings.startsAtCurrentLocation else { return nil }
        guard let coordinate = await locationProvider.requestCurrentCoordinate() else { return nil }
        guard RegionOfInterest.vysocina.contains(coordinate) else { return nil }

        return MapRegion.region(
            around: coordinate,
            widthMetres: MapRegion.currentLocationMetres,
            heightMetres: MapRegion.currentLocationMetres
        )
    }

    /// Remembers the viewport on screen, or forgets it when the map already
    /// opens there.
    func toggleSavedMapView() {
        setSavedMapView(settings.savedMapView == nil ? SavedMapView(region: visibleRegion) : nil)
    }

    func setSavedMapView(_ savedMapView: SavedMapView?) {
        guard settings.savedMapView != savedMapView else { return }
        settings.savedMapView = savedMapView
        settingsStore.save(settings)
    }

    func setStartsAtCurrentLocation(_ startsAtCurrentLocation: Bool) {
        guard settings.startsAtCurrentLocation != startsAtCurrentLocation else { return }
        settings.startsAtCurrentLocation = startsAtCurrentLocation
        settingsStore.save(settings)
    }

    func setAutoRefresh(enabled: Bool) {
        guard settings.autoRefreshEnabled != enabled else { return }
        settings.autoRefreshEnabled = enabled
        settingsStore.save(settings)
        restartAutoRefreshTask()
    }

    /// Sets how often the map refreshes itself.
    ///
    /// The value is clamped to ``AppSettings/minimumAutoRefreshInterval``: a
    /// shorter interval would only cost battery, because the feed does not
    /// update that quickly.
    func setAutoRefreshInterval(_ interval: TimeInterval) {
        let interval = AppSettings.clampedAutoRefreshInterval(interval)
        guard settings.autoRefreshInterval != interval else { return }
        settings.autoRefreshInterval = interval
        settingsStore.save(settings)
        restartAutoRefreshTask()
    }

    func stopAutoRefresh() {
        setAutoRefresh(enabled: false)
    }

    /// Remembers the chosen language.
    ///
    /// The change is written to `AppleLanguages`, which iOS reads while the app
    /// starts, so it is visible after the next launch.
    func setLanguage(_ language: AppLanguage) {
        guard settings.language != language else { return }
        settings.language = language
        settingsStore.save(settings)
        LanguageOverride.apply(language, to: languageDefaults)
    }

    private func restartAutoRefreshTask() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil

        guard settings.autoRefreshEnabled else { return }
        let interval = settings.autoRefreshInterval
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                await self.load()
            }
        }
    }

    /// Payloads a vehicle may stay missing before it leaves the map.
    static let missingLoadsBeforeRemoval = 5

    /// Vehicles that have gone quiet: the last position they were seen at, and
    /// how many payloads in a row have left them out.
    private var missingVehicles: [Int: MissingVehicle] = [:]

    private struct MissingVehicle {
        let vehicle: Vehicle
        var loads: Int
    }

    /// The traffic light version of the current view: the payload's vehicles,
    /// followed by the ones still being held on to.
    private func currentView() -> (live: [Vehicle], tracked: [Vehicle]) {
        let live = vehicles.filter(matchesFilter)
        let heldOn = missingVehicles.values
            .map(\.vehicle)
            .filter(matchesFilter)
            .sorted { $0.id < $1.id }
        return (live, live + heldOn)
    }

    private func matchesFilter(_ vehicle: Vehicle) -> Bool {
        switch filter {
        case .all:
            return true
        case .favourites:
            return favouriteLines.contains(vehicle.line)
        case .traction(let traction):
            return vehicle.traction == traction
        }
    }

    private func rebuildClusters() {
        let grid = self.grid ?? clusterer.grid(for: RegionOfInterest.vysocina.region)
        let view = currentView()

        // Clustering starts every marker at its new position, so the position a
        // marker was drawn at has to be carried over by identity. Without this a
        // refresh would place every marker exactly where it already is going.
        let drawn = Dictionary(clusters.map { ($0.id, $0.drawnCoordinate) }) { first, _ in first }
        let stale = Set(missingVehicles.keys)

        // The header counts what the feed is reporting, not what is still on
        // screen from earlier.
        vehicleCount = view.live.count
        clusters = clusterer.cluster(view.tracked, grid: grid).map { cluster in
            var cluster = cluster
            if let position = drawn[cluster.id] {
                cluster.drawnCoordinate = position
            }
            // A marker is stale only when nothing in it is being reported: a
            // grey marker carrying a live bus would be a lie.
            cluster.isStale = cluster.vehicles.allSatisfy { stale.contains($0.id) }
            return cluster
        }
        visibleVehicleCount = clusters.reduce(0) { $0 + $1.count }
        favouriteClusterIDs = Set(
            clusters
                .filter { cluster in
                    cluster.vehicles.contains { favouriteLines.contains($0.line) }
                }
                .map(\.id)
        )

        if let selectedClusterID, !clusters.contains(where: { $0.id == selectedClusterID }) {
            self.selectedClusterID = nil
            clearVehicleDetail()
        }

        moveMarkers()
    }

    /// Sends every marker on its way to the position the new payload gives it.
    ///
    /// Markers that are new appear where they are, and markers that disappeared
    /// are dropped: only the ones that were already on screen travel. Zooming
    /// re-cuts the grid, so the markers are new and land immediately, which is
    /// what you want when the map itself just moved.
    private func moveMarkers() {
        let travelling = clusters.reduce(into: [String: CLLocationCoordinate2D]()) { starts, cluster in
            guard MarkerMotion.hasMoved(from: cluster.drawnCoordinate, to: cluster.coordinate) else {
                return
            }
            starts[cluster.id] = cluster.drawnCoordinate
        }

        markerMotionTask?.cancel()
        markerMotionTask = nil

        guard !travelling.isEmpty else {
            placeMarkers()
            return
        }

        let duration = max(markerMotionDuration, 0)
        guard duration > 0 else {
            placeMarkers()
            return
        }

        let frame = Duration.seconds(1 / max(markerMotionFrameRate, 1))
        let travelTime = Duration.seconds(duration)

        markerMotionTask = Task { [weak self] in
            // Progress is read off the clock rather than counted in frames, so a
            // late frame skips ahead instead of making the movement stutter:
            // whatever the frame rate works out to be, the marker travels the
            // line at an even speed and arrives exactly at the end of `duration`.
            let startedAt = ContinuousClock.now
            while true {
                guard !Task.isCancelled, let self else { return }
                let progress = startedAt.duration(to: .now) / travelTime
                guard progress < 1 else { break }
                self.interpolate(from: travelling, progress: progress)
                try? await Task.sleep(for: frame)
            }
            guard !Task.isCancelled else { return }
            self?.placeMarkers()
        }
    }

    /// Puts every marker where the payload says it is, with no travelling left.
    private func placeMarkers() {
        for index in clusters.indices {
            clusters[index].drawnCoordinate = clusters[index].coordinate
        }
    }

    private func interpolate(from starts: [String: CLLocationCoordinate2D], progress: Double) {
        for index in clusters.indices {
            guard let start = starts[clusters[index].id] else { continue }
            clusters[index].drawnCoordinate = MarkerMotion.position(
                from: start,
                to: clusters[index].coordinate,
                progress: progress
            )
        }
    }

    private static func runningLines(in vehicles: [Vehicle]) -> [LineSummary] {
        var counts: [String: Int] = [:]
        var tractions: [String: [Traction: Int]] = [:]
        var operators: [String: [String: Int]] = [:]
        for vehicle in vehicles {
            // Grouped by the line number a passenger would recognise, not by
            // the operator prefixed code the feed sends.
            let line = vehicle.lineCode.number
            guard !line.isEmpty else { continue }
            counts[line, default: 0] += 1
            tractions[line, default: [:]][vehicle.traction, default: 0] += 1
            if let operatorCode = vehicle.lineCode.operatorCode {
                operators[line, default: [:]][operatorCode, default: 0] += 1
            }
        }

        let summaries = counts.map { line, count in
            LineSummary(
                line: line,
                operatorCode: Self.dominantCode(in: operators[line] ?? [:]),
                vehicleCount: count,
                traction: Self.dominantTraction(in: tractions[line] ?? [:]) ?? .unknown
            )
        }

        return summaries.sorted { lhs, rhs in
            if lhs.vehicleCount != rhs.vehicleCount {
                return lhs.vehicleCount > rhs.vehicleCount
            }
            return FavouriteLines.isOrderedBefore(lhs.line, rhs.line)
        }
    }

    private static func dominantCode(in counts: [String: Int]) -> String? {
        counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }?.key
    }

    private static func dominantTraction(in counts: [Traction: Int]) -> Traction? {
        counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key.sortIndex > rhs.key.sortIndex
        }?.key
    }

    private static func tractions(in vehicles: [Vehicle]) -> [Traction] {
        let present = Set(vehicles.map(\.traction))
        return Traction.allCases
            .filter { present.contains($0) }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? VehicleAPIError {
            return apiError.errorDescription
                ?? String(localized: "The vehicle feed could not be loaded.")
        }
        return error.localizedDescription
    }
}
