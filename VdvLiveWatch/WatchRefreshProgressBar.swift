import SwiftUI

/// Hairline across the top of the watch screen: how far the map is from its next
/// automatic refresh.
///
/// The phone draws the same thing along the top edge of its header card, and both
/// read their position from ``RefreshProgress``. A wrist has no room for the card,
/// so the bar is the whole of it - which is also the only thing on screen that says
/// the map is still being refreshed rather than merely drawn.
struct WatchRefreshProgressBar: View {
    /// Seconds between two automatic refreshes.
    let interval: TimeInterval
    /// When the data on screen was fetched.
    let lastUpdatedAt: Date?

    var body: some View {
        // Four steps a second rather than the display's sixty: on a hairline this
        // thin the difference is invisible, and the battery is not.
        TimelineView(.periodic(from: .now, by: Self.tick)) { context in
            bar(progress: RefreshProgress.fraction(
                lastUpdatedAt: lastUpdatedAt,
                now: context.date,
                interval: interval
            ))
        }
        .frame(height: Self.height)
    }

    /// How thin the hairline is, and how often it is redrawn.
    private static let height: CGFloat = 2
    private static let tick: TimeInterval = 1.0 / 4.0

    /// The full rainbow for the whole interval, revealed a little more with every
    /// frame, so the colours stay where they are instead of sliding along with the
    /// bar. The same one the phone reveals, because it is the same progress.
    private static let rainbow = LinearGradient(
        colors: [.red, .orange, .yellow, .green, .mint, .blue, .purple],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// How much of the rainbow shows through.
    private static let opacity: Double = 0.55

    private func bar(progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Barely there: the track is only a hint of how far the bar can
                // still grow.
                Rectangle().fill(.primary.opacity(0.07))

                Self.rainbow
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: proxy.size.width * progress)
                    }
                    .opacity(Self.opacity)
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        WatchRefreshProgressBar(interval: 15, lastUpdatedAt: .now.addingTimeInterval(-4))
        WatchRefreshProgressBar(interval: 15, lastUpdatedAt: .now)
        WatchRefreshProgressBar(interval: 15, lastUpdatedAt: nil)
    }
    .padding()
}
