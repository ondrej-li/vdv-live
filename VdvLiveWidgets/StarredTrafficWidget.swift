import AppIntents
import SwiftUI
import UIKit
import WidgetKit

/// The place a traffic widget looks around.
///
/// Empty means the reader's own position, which is what a widget added without any
/// configuration has to fall back on. Naming a stop makes the widget about that
/// stop's traffic, which is the question somebody planning a journey actually asks.
struct StarredTrafficIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Starred traffic"
    static let description = IntentDescription("The pinned lines' vehicles nearest to a place you choose.")

    @Parameter(title: "Around",
               description: "A stop to look around. Leave it empty to use your last known position.")
    var stop: StopEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Traffic around \(\.$stop)")
    }
}

/// One moment of the pinned lines' traffic around the reader.
struct StarredTrafficEntry: TimelineEntry {
    let date: Date
    let state: WidgetTrafficState
    /// The stop being looked around, `nil` when the widget is about the reader.
    let originName: String?
    /// The map drawn in place of an empty list, around the same place the vehicles
    /// were ranked from. `nil` when there is something to list, or when Apple Maps
    /// could not be reached - the widget then falls back to saying it found nothing.
    let mapImage: UIImage?

    /// What the header calls the place.
    var originLabel: String { originName ?? String(localized: "Near you") }
}

struct StarredTrafficProvider: AppIntentTimelineProvider {
    /// Traffic moves, so this asks again in a few minutes. WidgetKit decides how
    /// often it really grants that; the entries say what was true when asked.
    private static let refreshMinutes = 10

    static func limit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: return 1
        case .systemLarge, .systemExtraLarge: return 7
        default: return 4
        }
    }

    func placeholder(in context: Context) -> StarredTrafficEntry {
        StarredTrafficEntry(date: Date(), state: .needsPinnedLines, originName: nil, mapImage: nil)
    }

    func snapshot(for configuration: StarredTrafficIntent, in context: Context) async -> StarredTrafficEntry {
        await Self.entry(for: configuration, family: context.family)
    }

    func timeline(for configuration: StarredTrafficIntent,
                  in context: Context) async -> Timeline<StarredTrafficEntry> {
        let entry = await Self.entry(for: configuration, family: context.family)
        let next = entry.date.addingTimeInterval(TimeInterval(Self.refreshMinutes * 60))
        return Timeline(entries: [entry], policy: .after(next))
    }

    @MainActor
    private static func entry(for configuration: StarredTrafficIntent,
                              family: WidgetFamily) async -> StarredTrafficEntry {
        let origin = WidgetOrigin.resolve(stopNamed: configuration.stop?.name,
                                          in: StopPositions.shipped,
                                          position: LastKnownPositionStore().load())
        let state = await WidgetDataSource.trafficState(around: origin, limit: limit(for: family))
        return StarredTrafficEntry(date: Date(),
                                   state: state,
                                   originName: origin.name,
                                   mapImage: await map(for: state, from: origin, family: family))
    }

    /// A map when there is nothing to list, because "nothing nearby" reads better as
    /// the neighbourhood than as a sentence about it. It is drawn around the same
    /// place the vehicles were ranked from, so the two cannot disagree.
    @MainActor
    private static func map(for state: WidgetTrafficState,
                            from origin: WidgetOrigin,
                            family: WidgetFamily) async -> UIImage? {
        guard case .vehicles(let vehicles) = state, vehicles.isEmpty,
              let coordinate = origin.coordinate else { return nil }
        return await WidgetMap.image(around: coordinate, family: family)
    }
}

struct StarredTrafficWidget: Widget {
    static let kind = "cz.ondralinek.VdvLive.widget.traffic"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind,
                               intent: StarredTrafficIntent.self,
                               provider: StarredTrafficProvider()) { entry in
            StarredTrafficWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    if let map = entry.mapImage {
                        Image(uiImage: map)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(.fill.tertiary)
                    }
                }
        }
        .configurationDisplayName("Starred traffic")
        .description("The pinned lines' vehicles nearest to where you were.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StarredTrafficWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StarredTrafficEntry

    var body: some View {
        switch entry.state {
        case .needsPinnedLines:
            WidgetNote(icon: "star",
                       title: "No pinned lines",
                       detail: "Star a line in VDV Live and its vehicles appear here.")
        case .needsPosition:
            if let name = entry.originName {
                WidgetNote(icon: "mappin.slash",
                           title: "Stop not on the map",
                           detail: "The stop table has no position for \(name), so there is nothing to measure from.")
            } else {
                WidgetNote(icon: "location",
                           title: "Position not known yet",
                           detail: "Open VDV Live once near where you travel, and the widget finds what is close.")
            }
        case .vehicles(let vehicles):
            if vehicles.isEmpty {
                // The map is the widget; only a snapshot that could not be drawn
                // leaves anything to say.
                if entry.mapImage == nil {
                    emptyNearby
                } else {
                    Color.clear
                        .accessibilityLabel(Text("A map of your surroundings"))
                }
            } else {
                list(vehicles)
            }
        }
    }

    /// Shown only when the map could not be drawn: no network, or no position to draw
    /// around. The normal empty answer is the map itself.
    private var emptyNearby: some View {
        WidgetNote(icon: "checkmark.circle",
                   title: "Nothing nearby",
                   detail: "No vehicle of your pinned lines is within ten kilometres.")
    }

    private func list(_ vehicles: [NearbyVehicle]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: entry.originName == nil ? "star.fill" : "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.originLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text(entry.date, style: .time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if family == .systemSmall, let nearest = vehicles.first {
                NearestVehicleView(vehicle: nearest, others: vehicles.count - 1)
            } else {
                ForEach(vehicles) { vehicle in
                    TrafficRow(vehicle: vehicle)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The small family's one vehicle, drawn large enough to be read at a glance.
private struct NearestVehicleView: View {
    let vehicle: NearbyVehicle
    let others: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(vehicle.vehicle.displayLine)
                    .font(.title2.weight(.bold).monospacedDigit())
                Text(vehicle.vehicle.delay.displayText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.delayTint(vehicle.vehicle.delay))
            }
            if let destination = vehicle.vehicle.destination, !destination.isEmpty {
                Text(destination)
                    .font(.caption)
                    .lineLimit(1)
            }
            Text(vehicle.distanceText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            if others > 0 {
                Text(String(localized: "and \(others) more nearby"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One vehicle of a pinned line: which line, how late, how far.
private struct TrafficRow: View {
    let vehicle: NearbyVehicle

    var body: some View {
        HStack(spacing: 6) {
            Text(vehicle.vehicle.displayLine)
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.18), in: Capsule())

            Text(vehicle.vehicle.destination ?? String(localized: "Destination not in the timetable"))
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(vehicle.vehicle.delay.displayText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(WidgetPalette.delayTint(vehicle.vehicle.delay))

            Text(vehicle.distanceText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The shape every "nothing to show yet" state takes.
private struct WidgetNote: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
