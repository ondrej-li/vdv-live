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
    static func limit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: return 3
        case .systemLarge, .systemExtraLarge: return 7
        default: return 4
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
        VStack(alignment: .leading, spacing: 6) {
            header(stopName)
            if rows.isEmpty {
                Spacer(minLength: 0)
                Text("No departures in the next three hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(rows) { row in
                    DepartureRow(entry: row, isCompact: family == .systemSmall)
                }
                Spacer(minLength: 0)
            }
        }
    }

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
            Text(entry.date, style: .time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Departures from \(stopName)"))
    }
}

/// One departure, the way the board sheet draws it: line, destination, expected time.
private struct DepartureRow: View {
    let entry: StopBoardEntry
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(LineCode(raw: entry.lineNumber).number)
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.18), in: Capsule())

            if isCompact {
                Spacer(minLength: 0)
            } else {
                Text(entry.destination.map { $0.replacingOccurrences(of: ",", with: ", ") }
                     ?? String(localized: "Destination not in the timetable"))
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(entry.expectedText)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(WidgetPalette.delayTint(minutes: entry.delayMinutes))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }

    /// Built from translated pieces, so a Czech widget reads as Czech.
    private var spokenLabel: String {
        let line = LineCode(raw: entry.lineNumber).number
        let to = entry.destination.map { String(format: String(localized: "to %@"), $0) }
            ?? String(localized: "destination unknown")
        return String(localized: "Line \(line), \(to), scheduled \(entry.scheduled.text), expected \(entry.expectedText)")
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
