import SwiftUI

/// Banner used for problems and for the "nothing to show here" hint.
struct MapStatusBanner: View {
    enum Style {
        case warning
        case information
    }

    let message: String
    var style: Style = .warning
    /// Title of the trailing button, ignored when ``onAction`` is nil.
    var actionTitle: String = String(localized: "Retry")
    var onAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolTint)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let onAction {
                Button(actionTitle, action: onAction)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }

    private var symbolName: String {
        switch style {
        case .warning: return "exclamationmark.triangle.fill"
        case .information: return "info.circle.fill"
        }
    }

    private var symbolTint: Color {
        switch style {
        case .warning: return .orange
        case .information: return .accentColor
        }
    }
}
