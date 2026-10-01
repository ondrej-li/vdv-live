import SwiftUI

/// Every stop of the run, with the timetable's times moved by the delay the feed
/// reports.
///
/// Collapsed by default: the card is already busy, and the two or three stops a
/// passenger needs are in the rows above this.
struct VehicleStopsView: View {
    /// Run the vehicle is on, when the timetable has it.
    let run: ScheduledRun?
    /// Stop the feed last saw the vehicle at, highlighted in the list.
    let reportedStopName: String?
    /// Stop the vehicle is heading for, marked as well as the current one.
    let nextStopName: String?
    /// Minutes late, or `nil` when the feed has no delay information.
    let delayMinutes: Int?

    @State private var isExpanded = false

    var body: some View {
        if let run {
            DisclosureGroup(isExpanded: $isExpanded) {
                // The list is as long as the run is: it scrolls within a fixed
                // height so the map behind the card stays visible while it is open.
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(run.calls) { call in
                            row(for: call, in: run)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxHeight: 240)
            } label: {
                label(for: run)
            }
            .font(.caption)
        }
    }

    private func label(for run: ScheduledRun) -> some View {
        HStack(spacing: 6) {
            Text("All stops")
                .font(.subheadline)
            Text(String(format: String(localized: "%lld stops"), run.calls.count))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            if let delayMinutes, delayMinutes != 0 {
                Text(delayText(delayMinutes))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(delayTint(delayMinutes))
            }
        }
    }

    private func row(for call: ScheduledCall, in run: ScheduledRun) -> some View {
        let isCurrent = currentCall(in: run)?.stopID == call.stopID
        let isNext = !isCurrent && nextCall(in: run)?.stopID == call.stopID
        let weight: Font.Weight = isCurrent ? .semibold : (isNext ? .medium : .regular)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timeText(for: call))
                .font(.caption.monospacedDigit())
                .foregroundStyle(call.isOnRequest ? Color.secondary : Color.primary)
                .frame(width: 52, alignment: .leading)

            if let planned = plannedTime(for: call) {
                Text("(\(planned.text))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            } else {
                Color.clear.frame(width: 44)
            }

            Text(call.stopName)
                .font(.caption)
                .fontWeight(weight)
                .lineLimit(1)

            Spacer(minLength: 6)

            if let kilometres = call.distanceKilometres, isCurrent {
                Text(String(format: String(localized: "%lld km"), kilometres))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
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

    /// The time to show: the timetable's own time when the feed knows no delay,
    /// otherwise the time the vehicle should actually be there.
    private func timeText(for call: ScheduledCall) -> String {
        if call.isOnRequest { return String(localized: "on request") }
        guard let delayMinutes, delayMinutes != 0, let shifted = call.time(lateByMinutes: delayMinutes) else {
            return call.time?.text ?? "–"
        }
        return shifted.text
    }

    /// The published time, shown next to the delayed one so the delay is visible
    /// per stop and not just in the header.
    private func plannedTime(for call: ScheduledCall) -> TimeOfDay? {
        guard !call.isOnRequest, let delayMinutes, delayMinutes != 0 else { return nil }
        return call.time
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

    private func delayText(_ minutes: Int) -> String {
        minutes > 0
            ? String(format: String(localized: "+%lld min"), minutes)
            : String(format: String(localized: "%lld min"), minutes)
    }

    private func delayTint(_ minutes: Int) -> Color {
        minutes > 0 ? .orange : .green
    }
}
