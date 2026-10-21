import SwiftUI

/// A stop as something a list can be built from.
extension StopPosition: Identifiable {
    /// The name alone is not enough: two villages can share one.
    var id: String { "\(name)@\(latitude),\(longitude)" }
}

/// The board at a stop: what is due here, from the hour that has passed to the three
/// hours ahead, with the reader's own moment in the middle of it.
///
/// The timetables are published per line, so this loads only the lines the stop-to-lines
/// table says call here and lets `StopBoard` decide what belongs on the board.
struct StopBoardSheet: View {
    let stop: StopPosition
    let viewModel: VehicleMapViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var timetables: [LineTimetable] = []
    @State private var isLoading = true
    @State private var needsDownload = false
    @State private var now = TimeOfDay(Date())
    @State private var hasScrolled = false

    private var entries: [StopBoardEntry] {
        StopBoard.entries(at: stop.name,
                          in: timetables,
                          delays: viewModel.liveDelays,
                          now: now)
    }

    private var isStarred: Bool { viewModel.isStarred(stopNamed: stop.name) }

    /// The first row the reader has not missed, which is where the board opens.
    private var upcomingID: StopBoardEntry.ID? {
        entries.first { ($0.expected ?? $0.scheduled) >= now }?.id
    }

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(stop.name).font(.headline)
                            Text("Departures and arrivals")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.toggleStarredStop(named: stop.name)
                        } label: {
                            Image(systemName: isStarred ? "star.fill" : "star")
                        }
                        .accessibilityLabel(isStarred ? Text("Remove from starred stops")
                                                      : Text("Star this stop"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task { await loadTimetables() }
        .task {
            // The board is live: a minute later the row that was due may have left.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = TimeOfDay(Date())
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if needsDownload {
            ContentUnavailableView {
                Label("Timetables not downloaded", systemImage: "arrow.down.circle")
            } description: {
                Text("The board is read from the line timetables, which have to be downloaded once.")
            } actions: {
                Button("Download timetables") {
                    Task {
                        await viewModel.timetables.downloadIndex()
                        await loadTimetables()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if isLoading {
            ProgressView("Reading \(viewModel.lines(atStopNamed: stop.name).count) lines…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            ContentUnavailableView("Nothing due",
                                   systemImage: "clock",
                                   description: Text("No service calls here between an hour ago and three hours from now."))
        } else {
            board
        }
    }

    private var board: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    header
                    ForEach(entries) { entry in
                        row(entry)
                            .id(entry.id)
                            .overlay(alignment: .top) {
                                if entry.id == upcomingID {
                                    // The line between what has gone and what is coming.
                                    Rectangle()
                                        .fill(Color.accentColor)
                                        .frame(height: 2)
                                        .offset(y: -1)
                                }
                            }
                        Divider()
                    }
                }
            }
            .onAppear {
                guard !hasScrolled else { return }
                hasScrolled = true
                proxy.scrollTo(upcomingID ?? entries.first?.id, anchor: .center)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("Line").frame(width: 64, alignment: .leading)
            Text("Scheduled").frame(maxWidth: .infinity, alignment: .leading)
            Text("Expected").frame(maxWidth: .infinity, alignment: .leading)
            Text("Delay").frame(width: 84, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func row(_ entry: StopBoardEntry) -> some View {
        let readAt = entry.expected ?? entry.scheduled
        let isPast = readAt < now

        return HStack(spacing: 0) {
            Text(LineCode(raw: entry.lineNumber).number)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .frame(width: 64, alignment: .leading)

            Text(entry.scheduled.text)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.expected?.text ?? "—")
                .font(.subheadline.monospacedDigit().weight(entry.isOnTime ? .regular : .semibold))
                .foregroundStyle(expectedColour(entry))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(delayText(entry))
                .font(.caption.monospacedDigit())
                .foregroundStyle(expectedColour(entry))
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(isPast ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Line \(LineCode(raw: entry.lineNumber).number), "
            + "scheduled \(entry.scheduled.text), "
            + (entry.expected.map { "expected \($0.text)" } ?? "not departed yet")
            + ", \(delayText(entry))"
        )
    }

    private func expectedColour(_ entry: StopBoardEntry) -> Color {
        guard let delay = entry.delayMinutes else { return .primary }
        if delay <= 0 { return .green }
        return .orange
    }

    /// What the delay column says: `+5 min`, `on time`, or a dash when nothing is reporting.
    private func delayText(_ entry: StopBoardEntry) -> String {
        guard let delay = entry.delayMinutes else { return "—" }
        if delay == 0 { return String(localized: "on time") }
        return delay > 0 ? "+\(delay) min" : "\(delay) min"
    }

    private func loadTimetables() async {
        guard timetables.isEmpty else { return }
        needsDownload = false
        isLoading = true
        defer { isLoading = false }

        guard viewModel.timetables.isReady else {
            needsDownload = true
            return
        }
        var loaded: [LineTimetable] = []
        for line in viewModel.lines(atStopNamed: stop.name) {
            // A line the archive has moved on from must not take the whole board with it.
            if let timetable = try? await viewModel.timetables.timetable(forLine: line) {
                loaded.append(timetable)
            }
        }
        timetables = loaded
    }
}
