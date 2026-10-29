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
    /// Whether the board shows only the lines the user pinned.
    @State private var showsOnlyFavourites = false

    private var entries: [StopBoardEntry] {
        let all = StopBoard.entries(at: stop.name,
                                    in: timetables,
                                    delays: viewModel.liveDelays,
                                    now: now)
        guard showsOnlyFavourites else { return all }
        return all.filter { viewModel.favouriteLines.contains($0.lineNumber) }
    }

    private var hasFavouriteLines: Bool { !viewModel.favouriteLines.isEmpty }

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
                    if hasFavouriteLines {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showsOnlyFavourites.toggle()
                                hasScrolled = false
                            } label: {
                                Image(systemName: showsOnlyFavourites
                                      ? "line.3.horizontal.decrease.circle.fill"
                                      : "line.3.horizontal.decrease.circle")
                            }
                            .accessibilityLabel(showsOnlyFavourites
                                                ? Text("Show all lines")
                                                : Text("Show only pinned lines"))
                        }
                    }
                    // Right of the filter, left of Done: the stop's name, then what the
                    // board shows, then the stop itself, then the way out.
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
                        // Plain text, like the rest of the app's Done buttons.
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
            if showsOnlyFavourites {
                ContentUnavailableView("No pinned lines here",
                                       systemImage: "star",
                                       description: Text("None of the lines that call at this stop is one you pinned."))
            } else {
                ContentUnavailableView("Nothing due",
                                       systemImage: "clock",
                                       description: Text("No service calls here between an hour ago and three hours from now."))
            }
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
        HStack(spacing: 8) {
            Text("Line").frame(width: 52, alignment: .leading)
            Text("Destination").frame(maxWidth: .infinity, alignment: .leading)
            Text("Expected").frame(width: 76, alignment: .trailing)
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

        return HStack(spacing: 8) {
            Text(LineCode(raw: entry.lineNumber).number)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .frame(width: 52, alignment: .leading)

            // The destination leads, because it is the question a board answers:
            // which bus, going where. The timetable's own time and the delay follow
            // underneath, where they are read second.
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.destination.map(displayName) ?? String(localized: "Destination not in the timetable"))
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(entry.destination == nil ? Color.secondary : Color.primary)

                HStack(spacing: 6) {
                    Text(String(format: String(localized: "scheduled %@"), entry.scheduled.text))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if entry.delayMinutes != nil {
                        Text(delayText(entry))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(expectedColour(entry))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.expected?.text ?? "—")
                .font(.subheadline.monospacedDigit().weight(entry.isOnTime ? .regular : .semibold))
                .foregroundStyle(expectedColour(entry))
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(isPast ? 0.5 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spokenLabel(entry))
    }

    /// What VoiceOver reads for one row. Built from translated pieces rather than by
    /// joining English ones, so a Czech board reads as Czech.
    private func spokenLabel(_ entry: StopBoardEntry) -> String {
        let line = LineCode(raw: entry.lineNumber).number
        let expected = entry.expected.map { String(localized: "expected \($0.text)") }
            ?? String(localized: "not departed yet")
        let to = entry.destination.map { String(format: String(localized: "to %@"), displayName($0)) }
            ?? String(localized: "destination unknown")
        return String(
            localized: "Line \(line), \(to), scheduled \(entry.scheduled.text), \(expected), \(delayText(entry))"
        )
    }

    /// The archive writes "Zašovice,Nová Brtnice"; a person reads a space after the
    /// comma.
    private func displayName(_ stop: String) -> String {
        stop.replacingOccurrences(of: ",", with: ", ")
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
        // The minus sign comes from the number, so an early bus reads `-3 min`.
        return delay > 0
            ? String(localized: "+\(delay) min")
            : String(localized: "\(delay) min")
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
