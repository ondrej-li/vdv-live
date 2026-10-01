import SwiftUI

/// Card shown for the marker the user tapped.
struct VehicleDetailCard: View {
    let cluster: VehicleCluster
    /// Pinned lines, used to render the state of the star buttons.
    let favouriteLines: FavouriteLines
    /// Detail popup of the shown vehicle, once it has been fetched.
    var detail: VehicleDetail?
    var isLoadingDetail = false
    /// Published timetable of the line, once the timetable index is downloaded.
    var timetable: LineTimetable?
    var isLoadingTimetable = false
    /// Why the timetable is not on screen, when it is not. Nil while it is on its
    /// way, or when there is one to show.
    var timetableError: String?
    /// Whether the timetable index has been downloaded, which decides whether
    /// offering the download here makes sense.
    var isTimetableReady = true
    let onDownloadTimetable: () -> Void
    let onToggleFavourite: (String) -> Void
    let onSelectVehicle: (Vehicle) -> Void
    let onDismiss: () -> Void

    /// The card is a drawer: it opens short, with the few things a passenger came
    /// for, and is pulled up when the timetable is what they want.
    @State private var isExpanded = false
    /// Live drag distance, negative while the card is being pulled up.
    @State private var dragTranslation: CGFloat = 0
    /// Where the two states end, measured rather than assumed: a longer run, or a
    /// longer word in another language, would otherwise clip the wrong thing.
    @State private var peekHeight: CGFloat = 150
    @State private var fullHeight: CGFloat = 150

    private static let space = "vehicleDetailCard"
    private static let padding: CGFloat = 14
    /// How far the card has to travel before it changes state on release.
    private static let threshold: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            handle
            header
            VStack(alignment: .leading, spacing: 12) {
                shortContent
                marker { peekHeight = $0 + Self.padding }
            }
            if canExpand {
                longContent
            }
        }
        .padding(Self.padding)
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(name: Self.space)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
        .frame(height: cardHeight, alignment: .top)
        .clipped()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .gesture(drag, including: canExpand && !isExpanded ? .all : .none)
    }

    /// What the card opens with: the vehicle, the stop it is heading for, and the
    /// way into its timetable.
    @ViewBuilder
    private var shortContent: some View {
        if let vehicle = cluster.singleVehicle {
            VehicleDetailRow(vehicle: vehicle)
            if isLoadingDetail {
                loadingRow(String(localized: "Looking up this run…"))
            } else {
                if let next = detail?.nextStop {
                    detailRow(label: "Next stop", value: next.name, time: next.timeText)
                }
                timetableEntry
            }
        } else {
            BoundedList(maximumHeight: 220, minimumHeight: 44) { clusterRows }
        }
    }

    /// What the drawer adds: the rest of what the feed said about the run, and the
    /// timetable itself.
    @ViewBuilder
    private var longContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if cluster.isStale {
                Label("No recent data for this vehicle.", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Color.cardSecondary)
            }
            if let serviceNumber = detail?.serviceNumber {
                detailRow(label: "Service", value: serviceNumber)
            }
            if let stopName = detail?.stopName {
                detailRow(label: "Last stop", value: stopName, time: detail?.stop?.timeText)
            }
            if detail?.isBarrierFree == true {
                Label("Barrier-free", systemImage: "figure.roll")
                    .font(.caption)
                    .foregroundStyle(Color.cardSecondary)
            }
            if let run {
                VehicleStopsView(
                    run: run,
                    reportedStopName: detail?.stopName,
                    nextStopName: detail?.nextStop?.name,
                    delayMinutes: detail?.reportedDelayMinutes
                )
            }
        }
    }

    /// The way into the timetable: the summary row when there is a timetable to
    /// show, and otherwise the reason there is not.
    @ViewBuilder
    private var timetableEntry: some View {
        if let run {
            VehicleStopsSummary(
                run: run,
                delayMinutes: detail?.reportedDelayMinutes,
                isExpanded: isExpanded
            ) {
                withAnimation(.easeOut(duration: 0.25)) { isExpanded.toggle() }
            }
        } else if isLoadingTimetable {
            loadingRow(String(localized: "Looking up the timetable…"))
        } else if let timetableError {
            timetableProblem(timetableError)
        }
    }

    /// The run the vehicle is on, when the timetable knows the service number the
    /// feed reports for it.
    private var run: ScheduledRun? {
        timetable?.run(serviceNumber: detail?.serviceNumber)
    }

    /// Whether there is anything behind the short state: a merged marker has no
    /// run of its own to show.
    private var canExpand: Bool {
        cluster.singleVehicle != nil && detail != nil
    }

    /// The height to draw the card at: the state it is in, moved by the finger
    /// while it is being dragged, and never outside the two.
    private var cardHeight: CGFloat {
        let resting = isExpanded ? fullHeight : peekHeight
        return min(max(resting - dragTranslation, peekHeight), max(fullHeight, peekHeight))
    }

    /// The grabber. Decorative - the summary row below it is the way in for anyone
    /// who would rather tap than drag.
    private var handle: some View {
        Capsule()
            .fill(Color.cardHandle)
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    /// Reports where the short state ends: a zero height view placed after those
    /// rows and measured in the card's own coordinates.
    private func marker(_ update: @escaping (CGFloat) -> Void) -> some View {
        Color.clear
            .frame(height: 0)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(Self.space)).maxY
            } action: { bottom in
                update(bottom)
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                let distance = value.translation.height
                // Where the finger was heading, not only where it stopped: a quick
                // flick should be enough to change state.
                let fling = value.predictedEndTranslation.height
                withAnimation(.easeOut(duration: 0.25)) {
                    if distance < -Self.threshold || fling < -Self.threshold * 3 {
                        isExpanded = true
                    } else if distance > Self.threshold || fling > Self.threshold * 3 {
                        isExpanded = false
                    }
                    dragTranslation = 0
                }
            }
    }

    private func loadingRow(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.cardSecondary)
        }
    }

    /// The rows of a merged marker: one vehicle each, with its own star.
    private var clusterRows: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(cluster.vehicles) { vehicle in
                HStack(spacing: 10) {
                    Button {
                        onSelectVehicle(vehicle)
                    } label: {
                        VehicleDetailRow(vehicle: vehicle)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    favouriteButton(for: vehicle.line)
                }
            }
        }
    }

    /// Star that pins or unpins one line.
    ///
    /// A sibling of the row button rather than nested inside it, so that tapping
    /// the star cannot also fly the map to the vehicle.
    private func favouriteButton(for line: String) -> some View {
        let isFavourite = favouriteLines.contains(line)
        return Button {
            onToggleFavourite(line)
        } label: {
            Image(systemName: isFavourite ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(isFavourite ? VehicleFilter.favouriteTint : Color.cardSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isFavourite
                ? String(format: String(localized: "Unpin line %@"), line)
                : String(format: String(localized: "Pin line %@"), line)
        )
    }

    /// The timetable is not on screen: say why, and offer the download when that is
    /// what is missing.
    ///
    /// An index that has never been downloaded can be fixed from here; a line the
    /// published archive does not have cannot, and the message is the whole answer.
    private func timetableProblem(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.cardSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !isTimetableReady {
                Spacer(minLength: 6)
                Button("Download timetables", action: onDownloadTimetable)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func detailRow(
        label: LocalizedStringKey,
        value: String,
        time: String? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Wide enough for two lines of "Poslední zastávka", the longest
            // label the card uses, so the Czech wording is not cut off.
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.cardSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let time {
                Text(time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.cardSecondary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: cluster.dominantTraction.symbolName)
                .font(.title3)
                .foregroundStyle(cluster.dominantTraction.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(titleText)
                        .font(.headline)
                    if let licenceAreaCode = cluster.representative.lineCode.licenceAreaCode {
                        Text("licence area \(licenceAreaCode)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.cardSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                if cluster.count > 1 {
                    Text("Tap one to centre the map on it")
                        .font(.caption)
                        .foregroundStyle(Color.cardSecondary)
                }
            }

            Spacer(minLength: 8)

            if let vehicle = cluster.singleVehicle {
                favouriteButton(for: vehicle.line)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.cardSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close details"))
        }
    }

    private var titleText: String {
        if let vehicle = cluster.singleVehicle {
            return String(format: String(localized: "Line %@"), vehicle.displayLine)
        }
        return String(format: String(localized: "%lld vehicles here"), cluster.count)
    }
}

/// One vehicle inside ``VehicleDetailCard``.
struct VehicleDetailRow: View {
    let vehicle: Vehicle

    var body: some View {
        HStack(spacing: 10) {
            Text(vehicle.displayLine)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(vehicle.traction.tint.opacity(0.18), in: Capsule())

            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.destination ?? String(localized: "Destination not reported"))
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: vehicle.traction.symbolName)
                    Text(vehicle.traction.displayName)
                    Text("·")
                    Text("delay \(vehicle.delay.displayText)")
                        .foregroundStyle(vehicle.delay.tint)
                }
                .font(.caption)
                .foregroundStyle(Color.cardSecondary)
            }

            Spacer(minLength: 0)
        }
    }
}
