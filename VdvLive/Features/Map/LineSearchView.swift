import SwiftUI

/// Ad hoc search: a line number or a stop name, and the map goes there.
///
/// The pinned lines have a sheet of their own and so do the starred stops. This is for
/// the line somebody mentions on the phone, which is neither pinned nor starred and has
/// to be found once - so it searches what is running, what is pinned, and the shipped
/// stop names, and asks nothing of the network.
struct LineSearchView: View {
    let viewModel: VehicleMapViewModel
    /// Flies the map to the line; the caller closes the sheet.
    let onShowLine: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var boardStop: StopPosition?

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        Text("Type a line number, such as 420, or the name of a stop.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !lineMatches.isEmpty {
                    Section("Lines") {
                        ForEach(lineMatches) { summary in
                            lineRow(summary)
                        }
                    }
                }

                if !stopMatches.isEmpty {
                    Section("Stops") {
                        ForEach(stopMatches, id: \.self) { name in
                            stopRow(name)
                        }
                    }
                }

                if !query.isEmpty, lineMatches.isEmpty, stopMatches.isEmpty {
                    Section {
                        Text(String(format: String(localized: "Nothing matches “%@”."), query))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Line number or stop name"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $boardStop) { stop in
                StopBoardSheet(stop: stop, viewModel: viewModel)
            }
        }
    }

    private func lineRow(_ summary: LineSummary) -> some View {
        Button {
            onShowLine(summary.line)
        } label: {
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
                    Text(summary.descriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func stopRow(_ name: String) -> some View {
        Button {
            boardStop = viewModel.position(forStopNamed: name)
        } label: {
            HStack {
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var lineMatches: [LineSummary] {
        let pinned = viewModel.favouriteLines.orderedForDisplay.map { viewModel.summary(forLine: $0) }
        return LineSearch.matches(query, pinned: pinned, running: viewModel.runningLines)
    }

    /// Stop names from the shipped table, matched the way the map matches them, so
    /// `nova brtnice` finds `Nová Brtnice` and a search does not depend on accents.
    private var stopMatches: [String] {
        guard !query.isEmpty else { return [] }
        return StopPositions.shipped.names(matching: query, limit: Self.maximumResults)
    }

    private static let maximumResults = 12
}
