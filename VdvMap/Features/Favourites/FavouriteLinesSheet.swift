import SwiftUI

/// Sheet for managing pinned lines: the ones already pinned, and every line
/// that is reporting right now.
///
/// Lines can be pinned from here even when they are not running, which matters
/// for a line the user cares about that only runs at certain hours.
struct FavouriteLinesSheet: View {
    let favouriteLines: FavouriteLines
    let runningLines: [LineSummary]
    /// Summary for a pinned line, including the ones that are not running.
    let summaryForLine: (String) -> LineSummary
    /// Whether the map is showing pinned lines only.
    let showsOnlyPinned: Bool
    let onSetShowsOnlyPinned: (Bool) -> Void
    let onToggleLine: (String) -> Void
    /// Pins a line typed by hand.
    let onPinLine: (String) -> Void
    /// Asks the map to fly to the line.
    let onShowLine: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var isAddingLine = false
    @State private var draftLine = ""

    var body: some View {
        NavigationStack {
            List {
                onlyPinnedSection
                pinnedSection
                runningSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Pinned lines")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Find a line that is running"
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        draftLine = ""
                        isAddingLine = true
                    } label: {
                        Label("Pin a line", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Pin a line", isPresented: $isAddingLine) {
                TextField("Line number", text: $draftLine)
                    .keyboardType(.numbersAndPunctuation)
                Button("Pin") { onPinLine(draftLine) }
                    .disabled(FavouriteLines.normalize(draftLine).isEmpty)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Use the number the map shows, for example 420. A pinned line stays in the list even when it is not running.")
            }
        }
    }

    /// Switch for the quiet map. Hidden while nothing is pinned, because there
    /// would be nothing left to show.
    @ViewBuilder
    private var onlyPinnedSection: some View {
        if !favouriteLines.isEmpty {
            Section {
                Toggle(
                    "Show only pinned lines on the map",
                    isOn: Binding(
                        get: { showsOnlyPinned },
                        set: { onSetShowsOnlyPinned($0) }
                    )
                )
            } footer: {
                Text("Everything else stays hidden, which is easier on the eye when all you care about is one line. This is remembered for the next launch.")
            }
        }
    }

    private var pinnedSection: some View {
        Section {
            if favouriteLines.isEmpty {
                Text("No pinned lines yet. Pin one here, or tap a vehicle on the map and use the star.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(favouriteLines.orderedForDisplay, id: \.self) { line in
                    LineSummaryRow(
                        summary: summaryForLine(line),
                        isFavourite: true,
                        onToggle: { onToggleLine(line) },
                        onShow: { onShowLine(line) }
                    )
                    .swipeActions {
                        Button(role: .destructive) {
                            onToggleLine(line)
                        } label: {
                            Label("Unpin", systemImage: "star.slash")
                        }
                    }
                }
            }
        } header: {
            Text(
                favouriteLines.isEmpty
                    ? String(localized: "Pinned")
                    : String(format: String(localized: "Pinned (%lld)"), favouriteLines.count)
            )
        }
    }

    private var runningSection: some View {
        Section("Running now") {
            if visibleRunningLines.isEmpty {
                Text(
                    searchText.isEmpty
                        ? String(localized: "The feed is not reporting any vehicles at the moment.")
                        : String(
                            format: String(localized: "No running line matches “%@”."),
                            searchText
                        )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                ForEach(visibleRunningLines) { summary in
                    LineSummaryRow(
                        summary: summary,
                        isFavourite: favouriteLines.contains(summary.line),
                        onToggle: { onToggleLine(summary.line) },
                        onShow: { onShowLine(summary.line) }
                    )
                }
            }
        }
    }

    private var visibleRunningLines: [LineSummary] {
        let query = FavouriteLines.normalize(searchText)
        guard !query.isEmpty else { return runningLines }
        return runningLines.filter { $0.line.contains(query) }
    }
}

/// One line in ``FavouriteLinesSheet``.
private struct LineSummaryRow: View {
    let summary: LineSummary
    let isFavourite: Bool
    let onToggle: () -> Void
    let onShow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(summary.line)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(summary.isRunning ? Color.primary : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    summary.traction.tint.opacity(summary.isRunning ? 0.18 : 0.08),
                    in: Capsule()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.vehicleCountText)
                    .font(.subheadline)
                    .foregroundStyle(summary.isRunning ? Color.primary : Color.secondary)
                Text(summary.descriptionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: onToggle) {
                Image(systemName: isFavourite ? "star.fill" : "star")
                    .font(.body)
                    .foregroundStyle(isFavourite ? VehicleFilter.favouriteTint : Color.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isFavourite
                    ? String(format: String(localized: "Unpin line %@"), summary.line)
                    : String(format: String(localized: "Pin line %@"), summary.line)
            )
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onShow)
    }
}
