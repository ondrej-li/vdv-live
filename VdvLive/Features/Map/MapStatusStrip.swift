import SwiftUI

/// The quiet strip at the top of the map: how much is on screen and when it was
/// fetched, the filters, and the map's own controls.
///
/// Not a card. Two lines of type and two buttons do not need one, and a card over a
/// map is what this replaces: the map keeps the screen, and the strip borrows a band
/// of it and fades into the rest.
struct MapStatusStrip: View {
    let vehicleCount: Int
    let lastUpdatedAt: Date?
    let isRefreshing: Bool
    let isOffline: Bool
    /// Seconds between automatic refreshes while automatic refresh is on, and `nil`
    /// when it is off: the countdown is drawn only when there is one to draw. It is
    /// an indicator, not a control - switching automatic refresh is a preference.
    let refreshInterval: TimeInterval?
    let filters: [VehicleFilter]
    let selectedFilter: VehicleFilter
    let scale: MapScale?
    let isFollowingPosition: Bool
    /// Whether the map is turned away from north, which is the only time the compass
    /// earns a button.
    let isTurnedFromNorth: Bool

    let onSelectFilter: (VehicleFilter) -> Void
    let onShowWholeRegion: () -> Void
    let onToggleFollowPosition: () -> Void
    let onPointNorthUp: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let refreshInterval {
                RefreshProgressBar(interval: refreshInterval, lastUpdatedAt: lastUpdatedAt)
                    // It answers a question rather than asking one, so VoiceOver has
                    // nothing to do with it; the count line carries the same news.
                    .accessibilityHidden(true)
            }

            VStack(spacing: 8) {
                statusRow
                filterRow
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .background(scrim)
    }

    /// Fades the strip into the map instead of ruling a hard edge across it.
    private var scrim: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground).opacity(0.92),
                Color(uiColor: .systemBackground).opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 8)

            // The compass is not a standing control: it appears only once the map has
            // been turned, which is the only time it can do anything. Three permanent
            // unlabelled circles is what made this corner unreadable.
            if isTurnedFromNorth {
                control(systemName: "safari",
                        label: "Point north up",
                        action: onPointNorthUp)
            }
            control(systemName: "arrow.up.left.and.arrow.down.right",
                    label: "Show the whole region",
                    action: onShowWholeRegion)
            control(systemName: isFollowingPosition ? "location.fill" : "location",
                    label: isFollowingPosition
                        ? "Stop following my position"
                        : "Follow my position",
                    isActive: isFollowingPosition,
                    action: onToggleFollowPosition)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters, id: \.self) { filter in
                        chip(for: filter)
                    }
                }
                .padding(.vertical, 1)
            }

            if let scale {
                MapScaleLegend(scale: scale)
            }
        }
    }

    private func chip(for filter: VehicleFilter) -> some View {
        let isSelected = filter == selectedFilter
        return Button {
            onSelectFilter(filter)
        } label: {
            Text(filter.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    isSelected ? AnyShapeStyle(filter.tint) : AnyShapeStyle(.ultraThinMaterial),
                    in: Capsule()
                )
                .overlay {
                    if !isSelected {
                        Capsule().stroke(.primary.opacity(0.08), lineWidth: 0.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func control(
        systemName: String,
        label: LocalizedStringKey,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.75))
                .frame(width: 30, height: 30)
                .background(
                    isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.ultraThinMaterial),
                    in: Circle()
                )
                .overlay {
                    if !isActive {
                        Circle().stroke(.primary.opacity(0.08), lineWidth: 0.5)
                    }
                }
                .shadow(color: .black.opacity(0.1), radius: 5, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// What the feed last said, and how old that is.
    ///
    /// Being offline earns its own word: the count is what the feed last reported
    /// rather than what is out there now, and the age of what is on screen is the
    /// thing worth saying.
    private var statusText: String {
        let time = lastUpdatedAt?.formatted(date: .omitted, time: .standard)

        if isOffline {
            var parts = [String(localized: "Offline")]
            if let time {
                parts.append(String(format: String(localized: "last %@"), time))
            }
            return parts.joined(separator: " · ")
        }

        var parts = [String(format: String(localized: "%lld vehicles"), vehicleCount)]
        if let time {
            parts.append(String(format: String(localized: "updated %@"), time))
        } else if isRefreshing {
            parts.append(String(localized: "loading"))
        }
        return parts.joined(separator: " · ")
    }
}
