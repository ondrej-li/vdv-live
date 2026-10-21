import SwiftUI

/// The stop boards screen, reachable from the top bar without turning the map's stop
/// flags on.
///
/// It is the same list settings shows - starred stops first, then a search - because a
/// rider who taps this wants the stop they watch, and a rider who has starred nothing
/// wants a field to type a name into.
struct StopBoardsSheet: View {
    let viewModel: VehicleMapViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StarredStopsView(viewModel: viewModel)
                .navigationTitle("Stops")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
