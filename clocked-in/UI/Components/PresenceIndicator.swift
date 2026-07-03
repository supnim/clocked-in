import SwiftUI

struct PresenceIndicator: View {
    let status: PresenceStatus

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: status.color.opacity(0.5), radius: status == .online ? 2 : 0)
            .accessibilityLabel(status.accessibilityDescription)
    }
}

extension PresenceStatus {
    var color: Color {
        switch self {
        case .online:
            return .green
        case .away:
            return .yellow
        case .offline:
            return .gray
        case .ghost:
            return .purple
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .online: return "Online"
        case .away: return "Away"
        case .offline: return "Offline"
        case .ghost: return "Ghost"
        }
    }
}