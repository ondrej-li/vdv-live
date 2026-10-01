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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    @ViewBuilder
    private var content: some View {
        if let vehicle = cluster.singleVehicle {
            VehicleDetailRow(vehicle: vehicle)
            runSection
        } else {
            ScrollView {
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
            .frame(maxHeight: 220)
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
                .foregroundStyle(isFavourite ? VehicleFilter.favouriteTint : Color.secondary)
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

    /// What the map's own popup adds: which run this is, and where it is.
    ///
    /// ``detail`` is only fetched for single vehicle markers, so a merged
    /// marker simply has no extra rows.
    @ViewBuilder
    private var runSection: some View {
        if isLoadingDetail {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Looking up this run…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let detail {
            VStack(alignment: .leading, spacing: 8) {
                if cluster.isStale {                    Label("No recent data for this vehicle.", systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let serviceNumber = detail.serviceNumber {
                    detailRow(label: "Service", value: serviceNumber)
                }
                if let stopName = detail.stopName {
                    // The feed reports where the vehicle last was. The timetable
                    // adds the scheduled time when it knows that run at all.
                    detailRow(label: "Last stop", value: stopName, time: detail.stop?.timeText)
                }
                if let next = detail.nextStop {
                    detailRow(label: "Next stop", value: next.name, time: next.timeText)
                }
                if detail.isBarrierFree == true {
                    Label("Barrier-free", systemImage: "figure.roll")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let timetable {
                    VehicleStopsView(
                        run: timetable.run(serviceNumber: detail.serviceNumber),
                        reportedStopName: detail.stopName,
                        nextStopName: detail.nextStop?.name,
                        delayMinutes: detail.reportedDelayMinutes
                    )
                } else if isLoadingTimetable {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Looking up the timetable…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let timetableError {
                    timetableProblem(timetableError)
                }
            }
        } else if cluster.isStale {
            Label("No recent data for this vehicle.", systemImage: "wifi.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                if let destination = cluster.singleVehicle?.destination {
                    Text(destination)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if cluster.count > 1 {
                    Text("Tap one to centre the map on it")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let vehicle = cluster.singleVehicle {
                favouriteButton(for: vehicle.line)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}
