import SwiftUI

/// A list that takes the room its rows need, up to a limit, and scrolls past it.
///
/// Used for the card's lists: the card is a drawer over the map, so it has to grow
/// with a short list and stop growing at a long one. A plain `ScrollView` takes
/// whatever it is offered, which would leave the two short rows of a short run in
/// a tall card, and a `maxHeight` would leave the card guessing.
struct BoundedList<Content: View>: View {
    let maximumHeight: CGFloat
    let minimumHeight: CGFloat
    @ViewBuilder let content: () -> Content

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    contentHeight = height
                }
        }
        .frame(height: min(max(contentHeight, minimumHeight), maximumHeight))
    }
}
