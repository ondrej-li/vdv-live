import MapKit
import SwiftUI

/// The app's only screen: a map of the region with live vehicle positions.
struct VehicleMapView: View {
    @State private var viewModel: VehicleMapViewModel
    @State private var camera: MapCameraPosition
    @State private var isShowingFavourites = false
    @State private var isShowingSettings = false
    /// Size of the map, needed to turn a zoom level into a distance.
    @State private var mapSize: CGSize = .zero

    init(
        fetcher: VehicleFetching = AppDependencies.live.vehicleFetcher,
        favouriteLinesStore: FavouriteLinesPersisting = AppDependencies.live.favouriteLinesStore,
        settingsStore: AppSettingsStoring = AppDependencies.live.settingsStore,
        locationProvider: LocationProviding = AppDependencies.live.locationProvider
    ) {
        let viewModel = VehicleMapViewModel(
            fetcher: fetcher,
            favouriteLinesStore: favouriteLinesStore,
            settingsStore: settingsStore,
            locationProvider: locationProvider
        )
        _viewModel = State(initialValue: viewModel)
        // A viewport the user locked is known before the first frame, so the map
        // opens straight at it. Opening on the current location needs a position,
        // which only arrives later - see the second `task` in `body`.
        _camera = State(initialValue: .region(viewModel.launchRegion))
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
        .task { await viewModel.loadIfNeeded() }
        .task {
            // Opening on the current location needs a position, which is only
            // there after the first frame. Nothing happens unless the user asked
            // for it and a locked viewport is not already in the way.
            guard let region = await viewModel.currentLocationRegion() else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                camera = .region(region)
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
                onSelectFilter: { viewModel.select(filter: $0) },
                onRefresh: { Task { await viewModel.load() } },
                onRecenter: recenter,
                onToggleAutoRefresh: {
                    viewModel.setAutoRefresh(enabled: !viewModel.isAutoRefreshEnabled)
                },
                onShowFavourites: { isShowingFavourites = true },
                onToggleSavedMapView: { viewModel.toggleSavedMapView() },
                onShowSettings: { isShowingSettings = true }
            )

            if let errorMessage = viewModel.errorMessage {
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
            onSetStartsAtCurrentLocation: { viewModel.setStartsAtCurrentLocation($0) },
            onClearSavedMapView: { viewModel.setSavedMapView(nil) },
            isTimetableReady: viewModel.timetables.isReady,
            isDownloadingTimetables: viewModel.timetables.isDownloading,
            downloadedAt: viewModel.timetables.downloadedAt,
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
            onForgetTimetables: { viewModel.forgetTimetables() }
        )
    }

    /// Scale legend and detail card, both anchored to the bottom left.
    ///
    /// Sharing one stack is what keeps the legend just above the card when a
    /// vehicle is selected, and hard against the bottom edge when it is not.
    private var bottomOverlay: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                if let mapScale {
                    MapScaleLegend(scale: mapScale)
                        .padding(.leading, 16)
                }
                Spacer(minLength: 0)
            }

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
                onToggleFavourite: { viewModel.toggleFavourite(line: $0) },
                onSelectVehicle: focus,
                onDismiss: { viewModel.selectedClusterID = nil }
            )
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func recenter() {
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(RegionOfInterest.vysocina.region)
        }
    }

    /// Flies to the first vehicle reporting on `line`.
    ///
    /// The filter is nudged so the vehicle is actually on screen afterwards:
    /// pinned lines switch to the pinned filter, anything else falls back to
    /// showing every traction.
    private func focus(onLine line: String) {
        guard let vehicle = viewModel.firstVehicle(forLine: line) else { return }
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
    VehicleMapView(
        fetcher: AppDependencies.preview.vehicleFetcher,
        favouriteLinesStore: AppDependencies.preview.favouriteLinesStore,
        settingsStore: AppDependencies.preview.settingsStore,
        locationProvider: AppDependencies.preview.locationProvider
    )
}
