import SwiftUI

/// The app's navigation, floating over the map as one glass bar and a separate
/// search circle.
///
/// Search sits outside the bar on purpose: the other four are places to be, and a
/// fifth icon inside the capsule would read as a fifth place rather than as the way
/// to find something that is not pinned and not starred.
struct MapBottomBar: View {
    let isRefreshing: Bool

    let onShowLines: () -> Void
    let onShowStations: () -> Void
    let onReload: () -> Void
    let onShowSettings: () -> Void
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                item("Lines", action: onShowLines) {
                    Image(systemName: "star")
                }
                item("Stations", action: onShowStations) {
                    StopBoardGlyph()
                }
                item("Reload", action: onReload, isBusy: isRefreshing) {
                    Image(systemName: "arrow.clockwise")
                }
                item("Settings", action: onShowSettings) {
                    Image(systemName: "gearshape")
                }
            }
            .frame(height: 64)
            .padding(.horizontal, 4)
            .glassSurface(.capsule)
            .shadow(color: .black.opacity(0.16), radius: 16, y: 5)

            searchButton
        }
        .padding(.horizontal, 12)
    }

    private var searchButton: some View {
        Button(action: onSearch) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .glassSurface(.circle)
        .shadow(color: .black.opacity(0.16), radius: 16, y: 5)
        .accessibilityLabel(Text("Search"))
    }

    private func item<Glyph: View>(
        _ title: LocalizedStringKey,
        action: @escaping () -> Void,
        isBusy: Bool = false,
        @ViewBuilder glyph: () -> Glyph
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                glyph()
                    .font(.system(size: 18))
                    .frame(height: 20)
                    .opacity(isBusy ? 0 : 1)

                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .accessibilityLabel(Text(title))
    }
}

/// The bus stop sign, drawn to the size of the symbols beside it.
///
/// The emoji (`🚏`) is the neatest drawing of it, but it is a colour bitmap: it neither
/// takes the row's tint nor dims when the button is disabled. Two strokes cost nothing
/// and behave like a symbol.
struct StopBoardGlyph: View {
    /// Height of the glyph, a shade larger than the symbols it sits beside so that the
    /// sign's thin outline carries the same weight.
    private static let height: CGFloat = 15

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .strokeBorder(lineWidth: 1.2)
            Image(systemName: "bus.fill")
                .font(.system(size: 7.5, weight: .bold))
        }
        .frame(width: Self.height, height: Self.height)
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.2)
        MapBottomBar(isRefreshing: true,
                     onShowLines: {},
                     onShowStations: {},
                     onReload: {},
                     onShowSettings: {},
                     onSearch: {})
            .padding(.bottom, 20)
    }
}
