import AppIntents
import SwiftUI
import WidgetKit

/// The stop a board widget is about.
struct DepartureBoardIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Departure board"
    static let description = IntentDescription("The next departures from a stop you choose.")

    @Parameter(title: "Stop")
    var stop: StopEntity?

    /// The configuration sheet shows what the summary names, so the parameter has
    /// to be in it or the sheet has nothing to edit.
    static var parameterSummary: some ParameterSummary {
        Summary("Departures from \(\.$stop)")
    }
}

/// One moment of a stop's board.
struct DepartureBoardEntry: TimelineEntry {
    let date: Date
    let state: WidgetBoardState
}

struct DepartureBoardProvider: AppIntentTimelineProvider {
    /// How far ahead the timeline puts entries, and how often.
    ///
    /// Departures are minute-accurate even when the delays are not: the rows come
    /// from the timetable that is already on the device, so a new entry costs
    /// nothing and the "4 min" beside a bus ticks down while the widget sits on
    /// the home screen.
    private static let stepMinutes = 5
    private static let horizonMinutes = 30

    /// Rows a family has room for.
    ///
    /// Counted against the content area each family leaves after the system's
    /// margins: a medium widget fits three two-line rows and a header, four would be
    /// clipped - and a clipped row reads as a board that lost a bus.
    static func limit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: return 3
        case .systemLarge, .systemExtraLarge: return 7
        default: return 3
        }
    }

    func placeholder(in context: Context) -> DepartureBoardEntry {
        DepartureBoardEntry(date: Date(), state: .needsStop)
    }

    func snapshot(for configuration: DepartureBoardIntent, in context: Context) async -> DepartureBoardEntry {
        let material = await WidgetDataSource.boardMaterial(stopName: configuration.stop?.name)
        return DepartureBoardEntry(date: Date(),
                                   state: material.state(at: Date(), limit: Self.limit(for: context.family)))
    }

    func timeline(for configuration: DepartureBoardIntent,
                  in context: Context) async -> Timeline<DepartureBoardEntry> {
        let material = await WidgetDataSource.boardMaterial(stopName: configuration.stop?.name)
        let limit = Self.limit(for: context.family)
        let start = Date()
        let entries = stride(from: 0, through: Self.horizonMinutes, by: Self.stepMinutes).map { offset in
            let date = start.addingTimeInterval(TimeInterval(offset * 60))
            return DepartureBoardEntry(date: date, state: material.state(at: date, limit: limit))
        }
        return Timeline(entries: entries,
                        policy: .after(start.addingTimeInterval(TimeInterval(Self.horizonMinutes * 60))))
    }
}

struct DepartureBoardWidget: Widget {
    /// Stable identifier: changing it would leave every placed widget behind.
    static let kind = "cz.ondralinek.VdvLive.widget.departures"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind,
                               intent: DepartureBoardIntent.self,
                               provider: DepartureBoardProvider()) { entry in
            DepartureBoardWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Departure board")
        .description("What is leaving a stop you choose, with the feed's delays.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DepartureBoardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DepartureBoardEntry

    var body: some View {
        switch entry.state {
        case .needsStop:
            WidgetMessage(icon: "mappin.and.ellipse",
                          title: "Choose a stop",
                          detail: "Touch and hold this widget, choose Edit Widget, then tap Stop.")
        case .needsTimetables:
            WidgetMessage(icon: "arrow.down.circle",
                          title: "Timetables not downloaded",
                          detail: "Open VDV Live, then Settings, and download the timetables.")
        case let .board(stopName, rows):
            board(stopName: stopName, rows: rows)
        }
    }

    private func board(stopName: String, rows: [StopBoardEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(stopName)
            if rows.isEmpty {
                Spacer(minLength: 0)
                Text("No departures in the next three hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().opacity(0.4)
                        }
                        DepartureRow(entry: row, isCompact: family == .systemSmall)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The stop, and nothing else.
    ///
    /// The clock that used to sit on the right read as another departure time, which
    /// is the one thing a board must not be ambiguous about. The status bar already
    /// carries the time of day.
    private func header(_ stopName: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "bus")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(stopName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Departures from \(stopName)"))
    }
}

/// One departure: which line, where to, when it leaves and how it stands.
///
/// Every row carries a time, even before a vehicle reports - the timetable's own -
/// and spells the delay out in words, because a colour alone does not say "3 minutes
/// late" to somebody glancing at their home screen.
private struct DepartureRow: View {
    let entry: StopBoardEntry
    let isCompact: Bool

    private var time: TimeOfDay { entry.departureTime }
    private var tint: Color { WidgetPalette.statusTint(entry.status) }

    var body: some View {
        if isCompact {
            HStack(spacing: 6) {
                lineBadge
                Text(destination)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                timeAndStatus(alignment: .trailing)
            }
            .padding(.vertical, 3)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spokenLabel)
        } else {
            HStack(alignment: .center, spacing: 8) {
                lineBadge
                VStack(alignment: .leading, spacing: 1) {
                    Text(destination)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(statusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                timeAndStatus(alignment: .trailing)
            }
            .padding(.vertical, 3)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spokenLabel)
        }
    }

    private var lineBadge: some View {
        Text(LineCode(raw: entry.lineNumber).number)
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.18), in: Capsule())
    }

    private func timeAndStatus(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(time.text)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(entry.status == .scheduled ? Color.primary : tint)
            if isCompact {
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(tint)
            }
        }
    }

    private var destination: String {
        entry.destination.map { $0.replacingOccurrences(of: ",", with: ", ") }
            ?? String(localized: "Destination not in the timetable")
    }

    /// `+3 min`, `včas`, or `podle řádu` while nothing is reporting.
    private var statusText: String {
        switch entry.status {
        case .scheduled: return String(localized: "scheduled")
        case .onTime: return VehicleDelay.minutes(0).displayText
        case .late(let minutes): return VehicleDelay.minutes(minutes).displayText
        case .early(let minutes): return VehicleDelay.minutes(-minutes).displayText
        }
    }

    /// Built from translated pieces, so a Czech widget reads as Czech.
    private var spokenLabel: String {
        let line = LineCode(raw: entry.lineNumber).number
        return String(localized: "Line \(line) to \(destination): \(time.text), \(statusText)")
    }
}

/// The shape every "not yet" state takes, so they read as one thing.
private struct WidgetMessage: View {
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
