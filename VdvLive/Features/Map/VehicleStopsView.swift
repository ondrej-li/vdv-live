import SwiftUI

/// The row that offers the run's timetable: what it is and how long it is.
///
/// The card is a drawer, so this is both the summary of what is behind it and the
/// way in for anyone who would rather tap than drag.
struct VehicleStopsSummary: View {
    /// Run the vehicle is on, when the timetable has it.
    let run: ScheduledRun
    /// Minutes late, or `nil` when the feed has no delay information.
    let delayMinutes: Int?
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Text("All stops")
                    .font(.subheadline)
                Text(String(format: String(localized: "%lld stops"), run.calls.count))
                    .font(.caption)
                    .foregroundStyle(Color.cardSecondary)
                Spacer(minLength: 6)
                if let delayMinutes, delayMinutes != 0 {
                    Text(delayText(delayMinutes))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(delayTint(delayMinutes))
                }
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.cardSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func delayText(_ minutes: Int) -> String {
        minutes > 0
            ? String(format: String(localized: "+%lld min"), minutes)
            : String(format: String(localized: "%lld min"), minutes)
    }

    private func delayTint(_ minutes: Int) -> Color {
        minutes > 0 ? .orange : .green
    }
}

/// Every stop of the run, with the timetable's times moved by the delay the feed
/// reports.
///
/// Only drawn once the drawer is up: the two or three stops a passenger needs are
/// in the rows above it, in the short state the card opens in.
struct VehicleStopsView: View {
    /// Run the vehicle is on, when the timetable has it.
    let run: ScheduledRun
    /// Stop the feed last saw the vehicle at, highlighted in the list.
    let reportedStopName: String?
    /// Stop the vehicle is heading for, marked as well as the current one.
    let nextStopName: String?
    /// Minutes late, or `nil` when the feed has no delay information.
    let delayMinutes: Int?

    /// Tallest the list gets before it starts to scroll. The card is a drawer over
    /// the map, so a long run must not push the map off the screen.
    private static let maximumHeight: CGFloat = 240
    /// What a one or two stop run gets, so the list is not a sliver.
    private static let minimumHeight: CGFloat = 44

    var body: some View {
        // As tall as the run needs, up to the limit: the drawer itself is measured
        // from this, so the card grows by exactly what the list adds.
        BoundedList(maximumHeight: Self.maximumHeight, minimumHeight: Self.minimumHeight) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(run.calls) { call in
                    row(for: call, in: run)
                }
            }
            .padding(.top, 4)
        }
    }

    private func row(for call: ScheduledCall, in run: ScheduledRun) -> some View {
        let isCurrent = currentCall(in: run)?.stopID == call.stopID
        let isNext = !isCurrent && nextCall(in: run)?.stopID == call.stopID
        let weight: Font.Weight = isCurrent ? .semibold : (isNext ? .medium : .regular)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            timeColumn(for: call, in: run)

            if let planned = plannedTime(for: call, in: run) {
                Text("(\(planned.text))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.cardSecondary)
                    .frame(width: 44, alignment: .leading)
            } else {
                Color.clear.frame(width: 44)
            }

            // No line limit: a stop can have three parts, and the last one is as
            // much of the answer as the first two.
            Text(call.stopName)
                .font(.caption)
                .fontWeight(weight)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            if let kilometres = call.distanceKilometres, isCurrent {
                Text(String(format: String(localized: "%lld km"), kilometres))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.cardSecondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            isCurrent
                ? Color.accentColor.opacity(0.14)
                : (isNext ? Color.accentColor.opacity(0.07) : Color.clear),
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    /// The time, or the mark for a stop the vehicle only calls at on request.
    ///
    /// A request stop has no time to print - JDF writes a `<` where the clock
    /// would be - and printing words there instead made the list read as prose,
    /// and made the one column that is always a time the one that sometimes is
    /// not. The mark is what a timetable uses; VoiceOver still says the words.
    @ViewBuilder
    private func timeColumn(for call: ScheduledCall, in run: ScheduledRun) -> some View {
        if call.isOnRequest {
            Image(systemName: "hand.raised")
                .font(.caption2)
                .foregroundStyle(Color.cardSecondary)
                .frame(width: 52, alignment: .leading)
                .accessibilityLabel(Text("on request"))
        } else {
            Text(timeText(for: call, in: run))
                .font(.caption.monospacedDigit())
                .frame(width: 52, alignment: .leading)
        }
    }

    /// The time to show for a stop the vehicle still has ahead of it: the feed's
    /// delay moved onto the timetable's time. Behind the vehicle the timetable's
    /// own time stands, because there the delay is history rather than a
    /// prediction.
    private func timeText(for call: ScheduledCall, in run: ScheduledRun) -> String {
        guard isAhead(of: call, in: run),
              let delayMinutes, delayMinutes != 0,
              let shifted = call.time(lateByMinutes: delayMinutes) else {
            return call.time?.text ?? "–"
        }
        return shifted.text
    }

    /// The published time, shown beside the estimated one for the stops still
    /// ahead: the timetable is the promise and the delayed time is what the feed
    /// expects, and a passenger at a stop wants to see both.
    private func plannedTime(for call: ScheduledCall, in run: ScheduledRun) -> TimeOfDay? {
        guard !call.isOnRequest, isAhead(of: call, in: run), let delayMinutes, delayMinutes != 0 else {
            return nil
        }
        return call.time
    }

    /// Whether the vehicle still has this call ahead of it.
    ///
    /// Without a reported stop there is no way to tell where the vehicle is, and
    /// the whole run is treated as ahead of it.
    private func isAhead(of call: ScheduledCall, in run: ScheduledRun) -> Bool {
        guard let current = currentCall(in: run),
              let index = run.calls.firstIndex(where: { $0.id == call.id }),
              let currentIndex = run.calls.firstIndex(where: { $0.id == current.id }) else {
            return true
        }
        return index > currentIndex
    }

    private func currentCall(in run: ScheduledRun) -> ScheduledCall? {
        guard let reportedStopName else { return nil }
        return run.call(matchingStopName: reportedStopName)
    }

    /// The stop after the current one, which the feed's own popup names.
    private func nextCall(in run: ScheduledRun) -> ScheduledCall? {
        guard let nextStopName else { return nil }
        return run.call(matchingStopName: nextStopName)
    }
}
