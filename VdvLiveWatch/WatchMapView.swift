import MapKit
import SwiftUI

/// The whole watch app: a map of the pinned lines' vehicles, and nothing else.
///
/// No menu, no filter, no favourite star - the lines shown are the ones already
/// pinned on the phone, so every dot on screen is a favourite by definition. What
/// the dot cannot say in words it says in colour, and the digital crown is the
/// zoom. The map opens where the wearer is, because that is the one place every
/// glance starts from.
struct WatchMapView: View {
    @State private var model: WatchVehicleMapModel
    @State private var camera: MapCameraPosition
    @State private var region: MKCoordinateRegion
    @State private var zoom: Double = MapZoom.initialCrownValue
    /// Whether the map has already been put where the wearer is.
    ///
    /// Once per launch: after that the camera belongs to the finger and the crown,
    /// and a map that keeps recentring itself is one nobody can look at.
    @State private var hasCentredOnWearer = false
    /// The vehicle whose destination is being shown, if any.
    @State private var selected: Vehicle?

    /// How much of the screen's width the refresh hairline takes, centred, so that
    /// it begins and ends inside the straight part of the screen's rounded edge
    /// rather than running into the curve.
    private static let progressBarWidthFraction: CGFloat = 0.75
    /// How tall the hairline is, which is what the inset below is measured against.
    private static let progressBarHeight: CGFloat = 2
    /// How far the hairline sits above the bottom edge, and therefore how far above
    /// it anything else along the bottom has to sit. About the point where the
    /// screen's rounded corner has straightened out, which keeps the bar on the flat
    /// part of the edge without crowding it.
    private static let progressBarInset: CGFloat = 24
    /// How far a note sits above the bottom edge: clear of the hairline rather than
    /// on top of it.
    private static let noteInset: CGFloat = 30

    init() {
        // The map opens on the wearer rather than on the whole region. The zoom is
        // the one the crown opens at, and it is not disturbed again afterwards.
        let model = WatchVehicleMapModel(fetcher: WatchVehicleSource.fetcher)
        let opening = Self.openingRegion(around: model.lastKnownPosition)
        _model = State(initialValue: model)
        _camera = State(initialValue: .region(opening))
        _region = State(initialValue: opening)
    }

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom], selection: $selected) {
            // Where the wearer is, drawn here rather than with SwiftUI's own
            // `UserAnnotation`, which compiles for watchOS but puts nothing on the
            // map. Always on: a bus two kilometres away is only useful next to it.
            if let coordinate = model.userCoordinate {
                Annotation("", coordinate: coordinate) {
                    WatchUserDot()
                }
            }

            ForEach(model.vehicles) { vehicle in
                Annotation("", coordinate: vehicle.coordinate) {
                    WatchVehicleBadge(vehicle: vehicle)
                }
                .tag(vehicle)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .continuous) { context in
            // Panning and pinching move the map; the next crown turn has to start
            // from where the finger left it.
            region = context.region
        }
        .digitalCrownRotation(
            $zoom,
            from: 0,
            through: 1,
            by: 0.01,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: false
        )
        .onChange(of: zoom) { _, value in crownTurned(to: value) }
        .onChange(of: model.fixesReceived) { _, _ in
            // The first fix of the launch is the correction to where the map opened,
            // which was the last place the wearer was seen. Later ones are theirs to
            // pan away from.
            guard let coordinate = model.userCoordinate, !hasCentredOnWearer else { return }
            hasCentredOnWearer = true
            if focusesOnStart {
                focusOnWearer()
            } else {
                centre(on: coordinate)
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                // A double tap is the whole of the chrome a wrist can afford: no
                // button to find among the markers, and a gesture the map is
                // already listening for.
                focusOnWearer()
            }
        )
        .sheet(item: $selected) { vehicle in
            WatchVehicleDetailView(vehicle: vehicle)
        }
        .overlay(alignment: .bottom) { status }
        .overlay(alignment: .bottom) { progressBar }
        .task {
            await model.start()
            if selectsFirstVehicle { selected = model.vehicles.first }
        }
        .onDisappear { model.stop() }
    }

    /// `-watchSelectFirst` opens the detail sheet on launch, which is otherwise
    /// only reachable by tapping a marker and so cannot be photographed in a
    /// simulator.
    private var selectsFirstVehicle: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-watchSelectFirst")
        #else
        return false
        #endif
    }

    /// Where the map opens: on the wearer at the zoom the crown starts at, or on the
    /// whole region when there has never been a fix to remember.
    private static func openingRegion(around coordinate: CLLocationCoordinate2D?) -> MKCoordinateRegion {
        guard let coordinate else { return RegionOfInterest.vysocina.region }
        return MKCoordinateRegion(
            center: coordinate,
            span: MapZoom.span(forCrownValue: MapZoom.initialCrownValue)
        )
    }

    /// Puts the map on a position without touching the zoom the crown is at.
    private func centre(on coordinate: CLLocationCoordinate2D) {
        let updated = MKCoordinateRegion(center: coordinate, span: region.span)
        region = updated
        camera = .region(updated)
    }

    /// Puts the map back on the wearer, five kilometres across: the answer to
    /// "where am I" that a wrist can give without a menu to find it in.
    ///
    /// The position may be the one the system has just given or the one the last
    /// launch left behind - both are where the wearer is, and the second is the only
    /// answer there is indoors.
    private func focusOnWearer() {
        guard let coordinate = model.userCoordinate else { return }
        let focused = MapRegion.region(
            around: coordinate,
            widthMetres: MapRegion.focusMetres,
            heightMetres: MapRegion.focusMetres
        )
        hasCentredOnWearer = true
        region = focused
        camera = .region(focused)
        // Kept in step with the crown, so that the next turn carries on from this
        // window rather than jumping back to the zoom the map had before.
        zoom = MapZoom.crownValue(forLatitudeDelta: focused.span.latitudeDelta)
    }

    /// `-watchFocus` puts the map back on the wearer as soon as the first fix
    /// arrives. A double tap cannot be delivered to a simulator, so this stands in
    /// for one and goes through the same path.
    private var focusesOnStart: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-watchFocus")
        #else
        return false
        #endif
    }

    /// How far the map is from its next refresh, along the bottom edge where it
    /// reads as part of the map rather than as part of the clock.
    ///
    /// Three quarters of the screen's width, centred, so that the hairline begins
    /// and ends on the straight part of the screen's rounded edge instead of running
    /// into the curve.
    private var progressBar: some View {
        GeometryReader { proxy in
            WatchRefreshProgressBar(
                interval: WatchVehicleMapModel.refreshInterval,
                lastUpdatedAt: model.lastUpdatedAt
            )
            .frame(width: proxy.size.width * Self.progressBarWidthFraction)
            .position(
                x: proxy.size.width / 2,
                y: proxy.size.height - Self.progressBarInset - Self.progressBarHeight / 2
            )
        }
        // Measured from the bottom edge of the screen rather than of the safe area:
        // the map runs under the corner curve, and so should the bar.
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }

    private func crownTurned(to value: Double) {
        var updated = region
        updated.span = MapZoom.span(forCrownValue: value)
        region = updated
        camera = .region(updated)
    }

    /// Something worth saying, and nothing at all otherwise.
    @ViewBuilder
    private var status: some View {
        if model.favouriteLines.isEmpty {
            note(String(localized: "Pin lines on the phone"))
        } else if model.isLoading, model.vehicles.isEmpty {
            ProgressView()
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, Self.noteInset)
        } else if let message = model.errorMessage {
            // Said even when the map has vehicles on it: those are the last
            // positions the watch managed to fetch, and a marker that is stale but
            // looks live is worse than one that is labelled.
            note(message)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, Self.noteInset)
    }
}

/// Where the wearer is: the same blue dot the phone's map draws for itself.
struct WatchUserDot: View {
    var body: some View {
        Circle()
            .fill(.blue)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 1)
            .accessibilityLabel(String(localized: "My location"))
    }
}