import SwiftUI

struct FriendDetailView: View {
    let friendPresence: FriendPresence
    @Environment(\.dismiss) private var dismiss
    @State private var showNudgeFeedback = false
    @State private var isNudging = false
    @State private var nudgeError: AppError?
    @State private var removeError: AppError?

    /// Whether network-dependent actions are available
    private var canPerformActions: Bool {
        !NetworkMonitor.shared.connectionState.isOffline
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Profile section
                VStack(spacing: 12) {
                // Avatar
                AvatarView(
                    avatarURL: friendPresence.user.avatarUrl,
                    displayName: friendPresence.user.name,
                    size: 80
                )

                VStack(spacing: 4) {
                    Text(friendPresence.user.name)
                        .font(.system(size: 20, weight: .medium))

                    Text("@\(friendPresence.user.username)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    PresenceIndicator(status: friendPresence.status)
                }
            }

            // Status section
            VStack(alignment: .leading, spacing: 8) {
                Text("Status")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)

                if friendPresence.status == .offline {
                    Text("Last seen \(friendPresence.lastSeen.relativeTimeString())")
                        .font(.system(size: 14))
                } else {
                    Text("Active now")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)

            // Current activity section
            if let activity = friendPresence.currentActivity {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Activity")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        AppIconView(iconData: activity.appIcon, size: CGSize(width: 24, height: 24))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.appName)
                                .font(.system(size: 14, weight: .medium))

                            if let windowTitle = activity.windowTitle {
                                Text(windowTitle)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }

                            if let browserURL = activity.browserURL {
                                Text(browserURL)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }

                // Actions section
                VStack(spacing: 8) {
                    // Error banners
                    if let error = nudgeError {
                        ErrorBanner(
                            error: error,
                            onDismiss: { nudgeError = nil },
                            isCompact: true
                        )
                    }

                    if let error = removeError {
                        ErrorBanner(
                            error: error,
                            onRetry: removeFriend,
                            onDismiss: { removeError = nil },
                            isCompact: true
                        )
                    }

                    // Offline notice if applicable
                    if !canPerformActions && nudgeError == nil && removeError == nil {
                        HStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 11))
                            Text("Actions unavailable while offline")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }

                    // Nudge button
                    Button(action: sendNudge) {
                        HStack(spacing: 6) {
                            if isNudging {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: showNudgeFeedback ? "hand.thumbsup.fill" : "hand.wave.fill")
                                    .font(.system(size: 14))
                            }
                            Text(nudgeButtonText)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(nudgeButtonColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(nudgeButtonBackground)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPerformActions || isNudging || showNudgeFeedback || friendPresence.status == .offline)
                    .opacity(canPerformActions && friendPresence.status != .offline ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.2), value: showNudgeFeedback)

                    // Remove friend button
                    Button(action: removeFriend) {
                        Text("Remove Friend")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPerformActions)
                    .opacity(canPerformActions ? 1 : 0.5)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Nudge Button Styling

    private var nudgeButtonText: String {
        if showNudgeFeedback {
            return "Nudged!"
        }
        return "Nudge"
    }

    private var nudgeButtonColor: Color {
        if showNudgeFeedback {
            return .green
        }
        return .primary
    }

    private var nudgeButtonBackground: Color {
        if showNudgeFeedback {
            return Color.green.opacity(0.15)
        }
        return Color.accentColor.opacity(0.15)
    }

    // MARK: - Actions

    private func sendNudge() {
        guard !isNudging else { return }
        guard canPerformActions else {
            nudgeError = .network(message: "Cannot nudge while offline")
            return
        }

        isNudging = true
        nudgeError = nil

        Task {
            // WebSocket nudge doesn't throw, but we can check connection state
            if !WebSocketClient.shared.isConnected {
                await MainActor.run {
                    isNudging = false
                    nudgeError = .network(message: "Not connected to server")
                }
                return
            }

            await WebSocketClient.shared.sendNudge(to: friendPresence.uid)

            await MainActor.run {
                isNudging = false
                showNudgeFeedback = true
            }

            // Reset feedback after delay
            try? await Task.sleep(for: .seconds(2))

            await MainActor.run {
                showNudgeFeedback = false
            }
        }
    }

    private func removeFriend() {
        guard let friendId = friendPresence.user.id else {
            removeError = .unknown(message: "Cannot identify friend")
            return
        }
        guard canPerformActions else {
            removeError = .network(message: "Cannot remove friend while offline")
            return
        }

        removeError = nil

        Task {
            do {
                try await FriendService.shared.removeFriend(friendId)
                dismiss()
            } catch let err {
                removeError = AppError.from(err)
                ErrorHandler.shared.handle(err, context: "removeFriend", showToUser: false)
            }
        }
    }
}