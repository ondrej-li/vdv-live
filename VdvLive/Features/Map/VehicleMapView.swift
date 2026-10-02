import MapKit
import SwiftUI

/// The app's only screen: a map of the region with live vehicle positions.
struct VehicleMapView: View {
    @State private var viewModel: VehicleMapViewModel
    @State private var camera: MapCameraPosition
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingFavourites = false
    @State private var isShowingSettings = false
    /// Size of the map, needed to turn a zoom level into a distance.
    @State private var mapSize: CGSize = .zero
    /// Where the map is pointing. Kept from the last camera change, because a
    /// region cannot describe a direction and the reset has to.
    @State private var lastCamera: MapCamera?

    init(
        fetcher: VehicleFetching = AppDependencies.live.vehicleFetcher,
        favouriteLinesStore: FavouriteLinesPersisting = AppDependencies.live.favouriteLinesStore,
        settingsStore: AppSettingsStoring = AppDependencies.live.settingsStore,
        locationProvider: LocationProviding = AppDependencies.live.locationProvider
    ) {
        let viewModel = VehicleMapViewModel(
            payloadStore: VehiclePayloadFiles(),
            fetcher: fetcher,
            favouriteLinesStore: favouriteLinesStore,
            settingsStore: settingsStore,
            locationProvider: locationProvider
        )
        _viewModel = State(initialValue: viewModel)
        // A viewport the user locked is known before the first frame, so the map
        // opens straight at it. Opening on the current location needs a position,
        // which only arrives later - see the `task` in `body`. Following is known
        // before the first frame too, and outranks the opening viewport: the map
        // is going to move as soon as the user does.
        _camera = State(
            initialValue: viewModel.followsCurrentLocation
                ? Self.followingCamera
                : .region(viewModel.launchRegion)
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
            overlays
        }
        .overlay(alignment: .bottom) { bottomOverlay }
        .animation(.easeOut(duration: 0.2), value: viewModel.selectedClusterID)
        .sheet(isPresented: $isShowingFavourites) { favouritesSheet }
        .sheet(isPresented: $isShowingSettings) { settingsSheet }
        .onChange(of: viewModel.selectedClusterID) { _, _ in
            Task { await viewModel.selectionDidChange() }
        }
        .onChange(of: viewModel.clusters) { _, _ in
            // The markers change on every frame of a glide, which is what makes
            // the camera travel with the followed vehicle rather than jump to it.
            centreOnFollowedVehicle()
        }
        .onChange(of: viewModel.followsSelectedVehicle) { _, follows in
            // The vehicle only moves every so often, so it also has to be
            // centred when the follow starts rather than only when it next moves.
            guard follows else { return }
            centreOnFollowedVehicle()
        }
        .task { await viewModel.loadIfNeeded() }
        .task {
            // Opening on the current location needs a position, which is only
            // there after the first frame. Nothing happens unless the user asked
            // for it and a locked viewport is not already in the way.
            let region = await viewModel.currentLocationRegion()
            // The map draws the position itself, so when opening there did not
            // already ask for permission, this is what puts the prompt up.
            await viewModel.requestLocationPermissionIfNeeded()
            // Following is where the camera already started, and it outranks
            // opening on the location: it is the more specific instruction.
            guard let region, !viewModel.followsCurrentLocation else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                camera = .region(region)
            }
        }
        .onChange(of: viewModel.showsCurrentLocation) { _, showsCurrentLocation in
            // Turning it on mid-session should ask straight away rather than
            // waiting for the next launch.
            guard showsCurrentLocation else { return }
            Task { await viewModel.requestLocationPermissionIfNeeded() }
        }
        .onChange(of: viewModel.followsCurrentLocation) { _, followsCurrentLocation in
            // Turning it off leaves the map exactly where it is: following stops,
            // the camera does not move.
            guard followsCurrentLocation else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                camera = Self.followingCamera
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // The positions on screen are from before the app went away, so
                // they are greyed and replaced rather than left looking current.
                Task { await viewModel.appDidBecomeActive() }
            case .background:
                // The app is going away and may not come back, so whatever was
                // fetched this session is the freshest the next launch can show.
                viewModel.savePayloadForNextLaunch()
            default:
                break
            }
        }
        .onDisappear { viewModel.stopAutoRefresh() }
    }

    private var map: some View {
        Map(
            position: $camera,
            bounds: MapCameraBounds(
                centerCoordinateBounds: RegionOfInterest.vysocina.region,
                minimumDistance: 400,
                maximumDistance: 400_000
            ),
            selection: $viewModel.selectedClusterID
        ) {
            if viewModel.showsCurrentLocation {
                // The system's own blue dot, with its accuracy ring: MapKit keeps
                // it up to date, so all the app has to do is hold permission.
                UserAnnotation()
            }

            ForEach(viewModel.clusters) { cluster in
                Annotation(coordinate: cluster.drawnCoordinate) {
                    VehicleAnnotationView(
                        cluster: cluster,
                        isSelected: cluster.id == viewModel.selectedClusterID,
                        isFavourite: viewModel.favouriteClusterIDs.contains(cluster.id)
                    )
                } label: {
                    // The badge already carries the line or the count. The label
                    // MapKit draws underneath it would only repeat that text on
                    // an already busy map, and VoiceOver uses the accessibility
                    // label set on the badge view.
                    EmptyView()
                }
                .tag(cluster.id)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.updateVisibleRegion(context.region)
            lastCamera = context.camera
            // A pan is the user taking over. Following stops rather than pulling
            // the map back to the position under their finger.
            if camera.positionedByUser {
                if viewModel.followsCurrentLocation {
                    viewModel.setFollowsCurrentLocation(false)
                }
                if viewModel.followsSelectedVehicle {
                    viewModel.setFollowsSelectedVehicle(false)
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            mapSize = size
        }
        .ignoresSafeArea()
    }

    /// Scale bar for the current zoom level, once the map has a size.
    private var mapScale: MapScale? {
        MapScale.make(
            latitudeSpan: viewModel.visibleLatitudeDelta,
            mapHeight: mapSize.height
        )
    }

    /// What to say when the feed cannot be reached: whether there is anything on
    /// screen, and how old it is.
    private var offlineMessage: String {
        guard let lastUpdatedAt = viewModel.lastUpdatedAt else {
            return String(localized: "No connection to the feed.")
        }
        return String(
            format: String(
                localized: "No connection to the feed. Showing the last positions from %@."
            ),
            lastUpdatedAt.formatted(date: .omitted, time: .shortened)
        )
    }

    private var overlays: some View {
        VStack(spacing: 10) {
            MapHeaderBar(
                vehicleCount: viewModel.vehicleCount,
                lastUpdatedAt: viewModel.lastUpdatedAt,
                isRefreshing: viewModel.isRefreshing,
                filters: viewModel.availableFilters,
                selectedFilter: viewModel.filter,
                isAutoRefreshEnabled: viewModel.isAutoRefreshEnabled,
                refreshInterval: viewModel.isAutoRefreshEnabled ? viewModel.autoRefreshInterval : nil,
                favouriteLineCount: viewModel.favouriteLines.count,
                isMapViewSaved: viewModel.savedMapView != nil,
                isFollowingCurrentLocation: viewModel.followsCurrentLocation,
                isOffline: viewModel.isOffline,
                onSelectFilter: { viewModel.select(filter: $0) },
                onRefresh: { Task { await viewModel.load() } },
                onRecenter: recenter,
                onToggleAutoRefresh: {
                    viewModel.setAutoRefresh(enabled: !viewModel.isAutoRefreshEnabled)
                },
                onShowFavourites: { isShowingFavourites = true },
                onToggleFollowCurrentLocation: {
                    viewModel.setFollowsCurrentLocation(!viewModel.followsCurrentLocation)
                },
                onToggleSavedMapView: { viewModel.toggleSavedMapView() },
                onShowSettings: { isShowingSettings = true }
            )

            if viewModel.isOffline {
                // Not being able to reach the feed is a state rather than a
                // mistake: say what is on screen, how old it is, and offer the
                // retry.
                MapStatusBanner(
                    message: offlineMessage,
                    onAction: { Task { await viewModel.load() } }
                )
            } else if let errorMessage = viewModel.errorMessage {
                MapStatusBanner(
                    message: errorMessage,
                    onAction: { Task { await viewModel.load() } }
                )
            } else if viewModel.filter == .favourites, viewModel.favouriteLines.isEmpty {
                MapStatusBanner(
                    message: String(localized: "No pinned lines yet. Tap the star to pin a line number, or tap a vehicle on the map and use its star."),
                    style: .information
                )
            } else if viewModel.hasLoadedOnce,
                      viewModel.visibleVehicleCount == 0,
                      viewModel.showsOnlyPinnedLines,
                      let jumpToLine = viewModel.firstRunningPinnedLine {
                // Nothing in view but a pinned line is out there: offer the jump
                // instead of leaving the user staring at an empty map.
                MapStatusBanner(
                    message: String(localized: "Your pinned lines are not in this part of the map."),
                    style: .information,
                    actionTitle: String(format: String(localized: "Show line %@"), jumpToLine),
                    onAction: { focus(onLine: jumpToLine) }
                )
            } else if viewModel.hasLoadedOnce, viewModel.visibleVehicleCount == 0 {
                MapStatusBanner(message: emptyStateMessage, style: .information)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Wording for the "nothing on screen" hint.
    ///
    /// With the pinned filter on, the usual "no vehicles in this part of the
    /// map" would be wrong: it is the filter hiding them, not the viewport.
    private var emptyStateMessage: String {
        switch (viewModel.filter, viewModel.vehicleCount) {
        case (.favourites, 0):
            return String(localized: "None of your pinned lines are running right now.")
        case (.favourites, _):
            return String(localized: "Your pinned lines are not in this part of the map.")
        case (_, 0):
            return String(localized: "The feed is not reporting any vehicles at the moment.")
        default:
            return String(localized: "No vehicles in this part of the map.")
        }
    }

    private var favouritesSheet: some View {
        FavouriteLinesSheet(
            favouriteLines: viewModel.favouriteLines,
            runningLines: viewModel.runningLines,
            summaryForLine: { viewModel.summary(forLine: $0) },
            showsOnlyPinned: viewModel.showsOnlyPinnedLines,
            onSetShowsOnlyPinned: { viewModel.setShowsOnlyPinnedLines($0) },
            onToggleLine: { viewModel.toggleFavourite(line: $0) },
            onPinLine: { viewModel.pin(line: $0) },
            onShowLine: { line in
                isShowingFavourites = false
                focus(onLine: line)
            }
        )
    }

    private var settingsSheet: some View {
        SettingsSheet(
            settings: viewModel.settings,
            onSetAutoRefreshEnabled: { viewModel.setAutoRefresh(enabled: $0) },
            onSetAutoRefreshInterval: { viewModel.setAutoRefreshInterval($0) },
            onSetLanguage: { viewModel.setLanguage($0) },
            onSetClusterRadius: { viewModel.setClusterRadius($0) },
            onSetShowsCurrentLocation: { viewModel.setShowsCurrentLocation($0) },
            onSetFollowsCurrentLocation: { viewModel.setFollowsCurrentLocation($0) },
            onSetStartsAtCurrentLocation: { viewModel.setStartsAtCurrentLocation($0) },
            onClearSavedMapView: { viewModel.setSavedMapView(nil) },
            favouriteLines: viewModel.favouriteLines,
            runningLines: viewModel.runningLines,
            summaryForLine: { viewModel.summary(forLine: $0) },
            showsOnlyPinned: viewModel.showsOnlyPinnedLines,
            onSetShowsOnlyPinned: { viewModel.setShowsOnlyPinnedLines($0) },
            onToggleLine: { viewModel.toggleFavourite(line: $0) },
            onPinLine: { viewModel.pin(line: $0) },
            onShowLine: { line in
                // The settings screen has to get out of the way first, the same
                // way the pinned lines sheet does.
                isShowingSettings = false
                focus(onLine: line)
            },
            isTimetableReady: viewModel.timetables.isReady,
            isDownloadingTimetables: viewModel.timetables.isDownloading,
            isCheckingTimetables: viewModel.timetables.isCheckingForUpdates,
            downloadedAt: viewModel.timetables.downloadedAt,
            archivePublishedAt: viewModel.timetables.archivePublishedAt,
            timetableUpdate: viewModel.timetables.update,
            timetableErrorMessage: viewModel.timetables.errorMessage,
            knownLineCount: viewModel.timetables.knownLineCount,
            onDownloadTimetables: {
                Task {
                    await viewModel.timetables.downloadIndex()
                    // The card on screen should pick the timetable up straight
                    // away rather than at the next refresh.
                    await viewModel.reloadTimetableForSelection()
                }
            },
            onCheckTimetables: {
                Task { await viewModel.timetables.checkForUpdates() }
            },
            onForgetTimetables: { viewModel.forgetTimetables() }
        )
    }

    /// Scale legend and detail card, both anchored to the bottom left.
    ///
    /// Sharing one stack is what keeps the legend just above the card when a
    /// vehicle is selected, and hard against the bottom edge when it is not.
    private var bottomOverlay: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if let mapScale {
                    MapScaleLegend(scale: mapScale)
                }
                northUpButton
                Spacer(minLength: 0)
            }
            .padding(.leading, 16)

            detailCard
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var detailCard: some View {
        if let cluster = viewModel.selectedCluster {
            VehicleDetailCard(
                cluster: cluster,
                favouriteLines: viewModel.favouriteLines,
                detail: viewModel.vehicleDetail,
                isLoadingDetail: viewModel.isLoadingDetail,
                timetable: viewModel.lineTimetable,
                isLoadingTimetable: viewModel.isLoadingTimetable,
                timetableError: viewModel.timetableError,
                isTimetableReady: viewModel.timetables.isReady,
                isFollowing: viewModel.followsSelectedVehicle,
                onDownloadTimetable: {
                    Task {
                        await viewModel.timetables.downloadIndex()
                        // The card on screen should pick the timetable up straight
                        // away rather than at the next refresh.
                        await viewModel.reloadTimetableForSelection()
                    }
                },
                onToggleFollow: {
                    viewModel.setFollowsSelectedVehicle(!viewModel.followsSelectedVehicle)
                },
                onToggleFavourite: { viewModel.toggleFavourite(line: $0) },
                onSelectVehicle: focus,
                onDismiss: { viewModel.selectedClusterID = nil }
            )
            // A fresh card per vehicle: the drawer opens short again, and its two
            // heights are measured off the rows of the vehicle being shown.
            .id(cluster.id)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Camera position that makes MapKit keep the user in the middle as they move.
    ///
    /// The fallback covers a refused permission or a position that never arrives:
    /// the map then shows everything the camera bounds allow, which is the whole
    /// region.
    private static let followingCamera = MapCameraPosition.userLocation(
        followsHeading: false,
        fallback: .automatic
    )

    private func recenter() {
        // Deliberate camera moves take over from following, which would otherwise
        // pull the map straight back to the position.
        viewModel.setFollowsCurrentLocation(false)
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(RegionOfInterest.vysocina.region)
        }
    }

    /// Where the followed vehicle is being drawn, which is what the map centres.
    ///
    /// The drawn position rather than the reported one, so the camera travels
    /// with the marker as it glides to where the feed last saw it.
    private var followedCoordinate: CLLocationCoordinate2D? {
        guard let id = viewModel.followedClusterID else { return nil }
        return viewModel.clusters.first { $0.id == id }?.drawnCoordinate
    }

    /// Keeps the followed vehicle in the middle.
    ///
    /// The camera is built from the one on screen, so that the zoom and the
    /// direction the user has chosen for the map survive being dragged along.
    private func centreOnFollowedVehicle() {
        guard let coordinate = followedCoordinate, let current = lastCamera else { return }
        camera = .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: current.distance,
                heading: current.heading,
                pitch: current.pitch
            )
        )
    }

    /// Turns the map back to north, keeping the centre and the zoom where they are.
    ///
    /// The map can be turned and tilted with two fingers, and until now the only
    /// way back was the system compass: it appears only while the map is turned,
    /// and it sits at the opposite corner from everything else the app puts on
    /// screen.
    private func pointNorthUp() {
        // While the map is following the position it has its own north-up camera,
        // and a camera here would quietly take the following away with the turn.
        guard !viewModel.followsCurrentLocation else {
            withAnimation(.easeInOut(duration: 0.35)) {
                camera = Self.followingCamera
            }
            return
        }
        // The centre and the zoom are the ones already on screen, so only the
        // direction changes. Handing back a region here did nothing: a region
        // describes what to look at, and a turned map handed one keeps its turn.
        guard let current = lastCamera else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            camera = .camera(current.pointingNorth)
        }
    }

    /// Reset for the map's direction, which belongs with the scale legend: both
    /// answer the same question, which is how the map is being read.
    private var northUpButton: some View {
        Button(action: pointNorthUp) {
            Image(systemName: "safari")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 5, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Point north up"))
    }

    /// Flies to the first vehicle reporting on `line`.
    ///
    /// The filter is nudged so the vehicle is actually on screen afterwards:
    /// pinned lines switch to the pinned filter, anything else falls back to
    /// showing every traction.
    private func focus(onLine line: String) {
        guard let vehicle = viewModel.firstVehicle(forLine: line) else { return }
        // Flying somewhere is a deliberate camera move, so following gives way.
        viewModel.setFollowsCurrentLocation(false)
        if viewModel.isFavourite(line: line) {
            viewModel.select(filter: .favourites)
        } else if case .traction = viewModel.filter {
            viewModel.select(filter: .all)
        }
        withAnimation(.easeInOut(duration: 0.5)) {
            camera = .region(
                MKCoordinateRegion(
                    center: vehicle.coordinate,
                    span: RegionOfInterest.vehicleFocusSpan
                )
            )
        }
    }

    private func focus(on vehicle: Vehicle) {
        // Flying somewhere is a deliberate camera move, so following gives way.
        viewModel.setFollowsCurrentLocation(false)
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(
                MKCoordinateRegion(
                    center: vehicle.coordinate,
                    span: RegionOfInterest.vehicleFocusSpan
                )
            )
        }
    }
}

#Preview {
    // The preview runs on the debug-only sample feed, and a `#Preview` is
    // compiled in every configuration, so this one has to be kept out of the
    // Release build that gets archived.
    #if DEBUG
        VehicleMapView(
            fetcher: AppDependencies.preview.vehicleFetcher,
            favouriteLinesStore: AppDependencies.preview.favouriteLinesStore,
            settingsStore: AppDependencies.preview.settingsStore,
            locationProvider: AppDependencies.preview.locationProvider
        )
    #endif
}
