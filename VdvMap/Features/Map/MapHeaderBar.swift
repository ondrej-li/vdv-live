import SwiftUI

/// Floating bar above the map: what is on screen, when it was fetched, and the
/// controls that change it.
struct MapHeaderBar: View {
    let vehicleCount: Int
    let lastUpdatedAt: Date?
    let isRefreshing: Bool
    let filters: [VehicleFilter]
    let selectedFilter: VehicleFilter
    let isAutoRefreshEnabled: Bool
    /// Seconds between automatic refreshes, `nil` while automatic refresh is off.
    let refreshInterval: TimeInterval?
    let favouriteLineCount: Int
    let onSelectFilter: (VehicleFilter) -> Void
    let onRefresh: () -> Void
    let onRecenter: () -> Void
    let onToggleAutoRefresh: () -> Void
    let onShowFavourites: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                title
                Spacer(minLength: 8)
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
                iconButton(
                    systemName: favouriteLineCount == 0 ? "star" : "star.fill",
                    label: favouriteLineCount == 0
                        ? String(localized: "Pinned lines")
                        : String(
                            format: String(localized: "Pinned lines, %lld pinned"),
                            favouriteLineCount
                        ),
                    tint: favouriteLineCount == 0 ? nil : VehicleFilter.favouriteTint,
                    action: onShowFavourites
                )
                iconButton(
                    systemName: isAutoRefreshEnabled ? "pause.fill" : "play.fill",
                    label: isAutoRefreshEnabled
                        ? String(localized: "Turn automatic refresh off")
                        : String(localized: "Turn automatic refresh on"),
                    action: onToggleAutoRefresh
                )
                iconButton(
                    systemName: "arrow.clockwise",
                    label: String(localized: "Refresh vehicles"),
                    isEnabled: !isRefreshing,
                    action: onRefresh
                )
                iconButton(
                    systemName: "scope",
                    label: String(localized: "Back to Vysočina"),
                    action: onRecenter
                )
                iconButton(
                    systemName: "gearshape",
                    label: String(localized: "Settings"),
                    action: onShowSettings
                )
            }

            filterChips
        }
        .padding(12)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        )
        // The countdown lives on the top edge of the card. It is inset far
        // enough to stay on the straight part of that edge, so the line never
        // bends around the corners.
        .overlay(alignment: .top) {
            progressIndicator
                .padding(.horizontal, Self.cornerRadius)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private static let cornerRadius: CGFloat = 18

    @ViewBuilder
    private var progressIndicator: some View {
        if let refreshInterval {
            RefreshProgressBar(interval: refreshInterval, lastUpdatedAt: lastUpdatedAt)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Vysočina")
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        var parts = [String(format: String(localized: "%lld vehicles"), vehicleCount)]
        if let lastUpdatedAt {
            let time = lastUpdatedAt.formatted(date: .omitted, time: .standard)
            parts.append(String(format: String(localized: "updated %@"), time))
        } else if isRefreshing {
            parts.append(String(localized: "loading"))
        }
        return parts.joined(separator: " · ")
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(filters, id: \.self) { filter in
                    chip(
                        title: filter.displayName,
                        tint: filter.tint,
                        isSelected: filter == selectedFilter
                    ) {
                        onSelectFilter(filter)
                    }
                }
            }
        }
    }

    private func chip(
        title: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func iconButton(
        systemName: String,
        label: String,
        isEnabled: Bool = true,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint ?? Color.primary)
                .frame(width: 28, height: 28)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}
