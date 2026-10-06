import SwiftUI

/// Hairline that shows how far the map is from its next automatic refresh.
///
/// A rainbow that grows from the left across the top edge of the header card:
/// enough to answer "when does this update next?" without asking for attention.
/// The caller insets it so that it stays on the straight part of the top edge
/// and never wanders onto the rounded corners.
struct RefreshProgressBar: View {
    /// Seconds between two automatic refreshes.
    let interval: TimeInterval
    /// When the data on screen was fetched.
    let lastUpdatedAt: Date?

    /// How much of the interval has passed, clamped to `0...1`.
    ///
    /// The arithmetic lives in `RefreshProgress`, beside the watch's copy of this
    /// bar, so the two cannot disagree about what the bar means.
    static func progress(elapsed: TimeInterval, interval: TimeInterval) -> Double {
        RefreshProgress.fraction(elapsed: elapsed, interval: interval)
    }

    var body: some View {
        // Ticks with the display instead of on a timer: a 0.25 second timer is
        // four visible steps per second, which reads as a stutter.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            bar(progress: Self.progress(elapsed: elapsed(at: context.date), interval: interval))
        }
        .frame(height: Self.height)
    }

    /// How thin the hairline is. Thin enough to read as a light rather than as
    /// part of the card.
    private static let height: CGFloat = 2
    private static let cornerRadius: CGFloat = 1

    /// The full rainbow for the whole interval, revealed a little more with
    /// every frame, so the colours stay where they are instead of sliding along
    /// with the bar.
    private static let rainbow = LinearGradient(
        colors: [.red, .orange, .yellow, .green, .mint, .blue, .purple],
        startPoint: .leading,
        endPoint: .trailing
    )

    private func elapsed(at date: Date) -> TimeInterval {
        guard let lastUpdatedAt else { return interval }
        return date.timeIntervalSince(lastUpdatedAt)
    }

    private func bar(progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Barely there: the track is only a hint of how far the bar can
                // still grow, and the rainbow itself is translucent so it reads
                // as a light in the corner of the eye rather than as chrome.
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(.primary.opacity(0.07))

                Self.rainbow
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: proxy.size.width * progress)
                    }
                    .opacity(Self.opacity)
            }
        }
    }

    /// How much of the rainbow shows through.
    private static let opacity: Double = 0.55
}

#Preview {
    VStack(spacing: 20) {
        RefreshProgressBar(interval: 15, lastUpdatedAt: .now.addingTimeInterval(-5))
        RefreshProgressBar(interval: 15, lastUpdatedAt: .now)
        RefreshProgressBar(interval: 15, lastUpdatedAt: .now.addingTimeInterval(-15))
        RefreshProgressBar(interval: 15, lastUpdatedAt: nil)
    }
    .padding(40)
}
