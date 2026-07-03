import SwiftUI

/// Banner displayed when the app is offline or reconnecting
/// Shows connection state, last update time, and allows manual retry
struct OfflineBanner: View {
    /// Compact mode for menu bar (smaller text, no padding)
    var isCompact: Bool = false

    /// Called when user taps to retry
    var onRetry: (() -> Void)? = nil

    @State private var isAnimatingReconnect = false

    private var connectionState: ConnectionState {
        NetworkMonitor.shared.connectionState
    }

    private var lastUpdatedDescription: String? {
        CachedFriendsService.shared.lastUpdatedDescription
    }

    var body: some View {
        if isCompact {
            compactBanner
        } else {
            fullBanner
        }
    }

    // MARK: - Compact Banner (for CompactNotchView)

    private var compactBanner: some View {
        Button(action: handleRetry) {
            HStack(spacing: 4) {
                connectionIcon
                    .font(.caption2)
                    .foregroundColor(iconColor)

                Text(compactText)
                    .font(.caption2)
                    .foregroundColor(textColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help("Tap to retry connection")
    }

    // MARK: - Full Banner (for LobbyView header)

    private var fullBanner: some View {
        Button(action: handleRetry) {
            HStack(spacing: 8) {
                connectionIcon
                    .font(.caption)
                    .foregroundColor(iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(connectionState.displayText)
                        .font(.caption.weight(.medium))
                        .foregroundColor(textColor)

                    if let lastUpdated = lastUpdatedDescription {
                        Text("Last updated \(lastUpdated)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Retry indicator
                if case .offline = connectionState {
                    Text("Tap to retry")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Views

    @ViewBuilder
    private var connectionIcon: some View {
        switch connectionState {
        case .online:
            Image(systemName: "wifi")
        case .offline:
            Image(systemName: "wifi.slash")
        case .reconnecting:
            Image(systemName: "arrow.triangle.2.circlepath")
                .rotationEffect(.degrees(isAnimatingReconnect ? 360 : 0))
                .animation(
                    .linear(duration: 1.0).repeatForever(autoreverses: false),
                    value: isAnimatingReconnect
                )
                .onAppear { isAnimatingReconnect = true }
                .onDisappear { isAnimatingReconnect = false }
        }
    }

    // MARK: - Computed Properties

    private var compactText: String {
        switch connectionState {
        case .online:
            return "Online"
        case .offline:
            if let lastUpdated = lastUpdatedDescription {
                return "Offline - \(lastUpdated)"
            }
            return "Offline"
        case .reconnecting(let attempt, _):
            return "Reconnecting... (\(attempt))"
        }
    }

    private var iconColor: Color {
        switch connectionState {
        case .online:
            return .green
        case .offline:
            return .orange
        case .reconnecting:
            return .yellow
        }
    }

    private var textColor: Color {
        switch connectionState {
        case .online:
            return .green
        case .offline:
            return .orange
        case .reconnecting:
            return .yellow
        }
    }

    private var backgroundColor: Color {
        switch connectionState {
        case .online:
            return .green.opacity(0.1)
        case .offline:
            return .orange.opacity(0.1)
        case .reconnecting:
            return .yellow.opacity(0.1)
        }
    }

    // MARK: - Actions

    private func handleRetry() {
        onRetry?()
        NetworkMonitor.shared.retryConnection()
    }
}

// MARK: - Preview

#Preview("Offline States") {
    VStack(spacing: 20) {
        // Compact banners
        VStack(alignment: .leading, spacing: 8) {
            Text("Compact (Menu Bar)")
                .font(.caption)
                .foregroundColor(.secondary)

            OfflineBanner(isCompact: true)
        }

        Divider()

        // Full banners
        VStack(alignment: .leading, spacing: 8) {
            Text("Full (Lobby Header)")
                .font(.caption)
                .foregroundColor(.secondary)

            OfflineBanner(isCompact: false)
        }
    }
    .padding()
    .frame(width: 300)
    .background(Color.black.opacity(0.8))
}
