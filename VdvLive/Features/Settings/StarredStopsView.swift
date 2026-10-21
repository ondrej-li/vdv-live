import SwiftUI

/// The stops the user starred, and a way to add one by name.
///
/// Reached from settings rather than from the map, because a starred stop has to be
/// reachable when the flags are turned off - the whole point of starring one is not
/// having to find it again.
struct StarredStopsView: View {
    let viewModel: VehicleMapViewModel

    @State private var search = ""
    @State private var boardStop: StopPosition?

    private var matches: [String] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return StopPositions.shipped.allNames
            .filter { $0.localizedCaseInsensitiveContains(query) && !viewModel.isStarred(stopNamed: $0) }
            .prefix(20)
            .map { $0 }
    }

    var body: some View {
        List {
            Section {
                if viewModel.starredStops.isEmpty {
                    Text("No starred stops yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.starredStops.orderedForDisplay, id: \.self) { name in
                    Button {
                        boardStop = viewModel.position(forStopNamed: name)
                    } label: {
                        HStack {
                            Text(name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete { offsets in
                    let names = viewModel.starredStops.orderedForDisplay
                    for index in offsets where index < names.count {
                        viewModel.toggleStarredStop(named: names[index])
                    }
                }
            } footer: {
                Text("Tap a stop for its departures. Swipe to remove.")
            }

            Section("Add a stop") {
                TextField("Search by name", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                ForEach(matches, id: \.self) { name in
                    Button {
                        viewModel.toggleStarredStop(named: name)
                        search = ""
                    } label: {
                        HStack {
                            Text(name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "star")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if search.isEmpty {
                    Text("Stops can also be starred from the board, after tapping their flag on the map.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(item: $boardStop) { stop in
            StopBoardSheet(stop: stop, viewModel: viewModel)
        }
    }
}
