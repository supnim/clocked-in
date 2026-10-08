import SwiftUI

/// Groups friends by the app they are using
struct AppGroup: Identifiable {
    let appName: String
    let bundleId: String
    let appIcon: Data?
    let friends: [FriendPresence]

    var id: String { bundleId }
}

struct LobbyView: View {
    let viewModel: NotchViewModel

    @State private var friendToRemove: FriendPresence?
    @State private var actionError: AppError?

    /// Whether we're currently offline/reconnecting
    private var isOffline: Bool {
        NetworkMonitor.shared.connectionState.isOffline
    }

    private func showFriendDetail(_ presence: FriendPresence) {
        viewModel.showContent(.friendDetail(presence.uid))
    }

    /// Group online friends by their current app
    private func groupFriendsByApp(_ friends: [FriendPresence]) -> [AppGroup] {
        var groups: [String: (appName: String, appIcon: Data?, friends: [FriendPresence])] = [:]

        for friend in friends {
            guard let activity = friend.currentActivity, !activity.bundleId.isEmpty else {
                // Friends without activity go into "Unknown" group
                groups["_unknown", default: ("Unknown", nil, [])].friends.append(friend)
                continue
            }

            if groups[activity.bundleId] == nil {
                groups[activity.bundleId] = (activity.appName, activity.appIcon, [])
            }
            groups[activity.bundleId]?.friends.append(friend)
        }

        // Sort by number of friends (most first), then alphabetically
        return groups.map { bundleId, data in
            AppGroup(appName: data.appName, bundleId: bundleId, appIcon: data.appIcon, friends: data.friends)
        }.sorted { lhs, rhs in
            if lhs.friends.count != rhs.friends.count {
                return lhs.friends.count > rhs.friends.count
            }
            return lhs.appName < rhs.appName
        }
    }

    /// Check if current user is in this app
    private func isUserInApp(_ bundleId: String, currentActivity: Activity?) -> Bool {
        guard let userActivity = currentActivity,
              !userActivity.bundleId.isEmpty,
              !bundleId.isEmpty else {
            return false
        }
        return userActivity.bundleId == bundleId
    }

    // MARK: - Row Actions

    private func nudge(_ presence: FriendPresence) {
        guard WebSocketClient.shared.isConnected else {
            actionError = .network(message: "Not connected to server")
            return
        }
        Task {
            await WebSocketClient.shared.sendNudge(to: presence.uid)
        }
    }

    private func remove(_ presence: FriendPresence) {
        let friendId = presence.uid
        Task {
            do {
                try await FriendService.shared.removeFriend(friendId)
                FriendService.shared.forgetFriendLocally(friendId)
            } catch let err {
                actionError = AppError.from(err)
                ErrorHandler.shared.handle(err, context: "removeFriend", showToUser: false)
            }
        }
    }

    // MARK: - Empty-list States

    /// No friends to show yet: distinguish "no network", "still connecting" and "really no friends".
    @ViewBuilder
    private var emptyListContent: some View {
        let ws = WebSocketClient.shared
        if NetworkMonitor.shared.isOffline {
            statusMessage(
                icon: "wifi.slash",
                title: "You're offline",
                detail: "Friends will appear when your connection is back.",
                showRetry: false
            )
        } else if !ws.isConnected {
            // initial_presence always follows a successful connect, so until we're
            // connected we can't tell whether the list is really empty.
            if ws.isReconnecting {
                statusMessage(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Reconnecting…",
                    detail: nil,
                    showRetry: false,
                    showSpinner: true
                )
            } else {
                statusMessage(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Connecting…",
                    detail: "If this takes a while, the server may be unreachable.",
                    showRetry: true,
                    showSpinner: true
                )
            }
        } else if ws.latestInitialPresence == nil {
            // Connected, waiting for the server's initial friend list
            statusMessage(
                icon: "person.2",
                title: "Loading friends…",
                detail: nil,
                showRetry: false,
                showSpinner: true
            )
        } else {
            EmptyStateView(viewModel: viewModel)
        }
    }

    private func statusMessage(
        icon: String,
        title: String,
        detail: String?,
        showRetry: Bool,
        showSpinner: Bool = false
    ) -> some View {
        VStack(spacing: 10) {
            if showSpinner {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if showRetry {
                Button("Retry") {
                    NetworkMonitor.shared.retryConnection()
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    var body: some View {
        // Access singletons directly in body for proper @Observable tracking
        let presenceListener = PresenceListener.shared
        let presenceManager = PresenceManager.shared
        let currentUserActivity = presenceManager.currentActivity

        Group {
            if presenceListener.friendsPresence.isEmpty {
                emptyListContent
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let error = actionError {
                            ErrorBanner(
                                error: error,
                                onDismiss: { actionError = nil },
                                isCompact: true
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }

                        // Offline banner at top when disconnected
                        if isOffline {
                            OfflineBanner(isCompact: false)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)

                            // Show cached data notice
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption2)
                                Text("Showing cached data")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        }

                        // Group online friends by app
                        let appGroups = groupFriendsByApp(presenceListener.onlineFriends)

                        if !appGroups.isEmpty {
                            ForEach(appGroups) { group in
                                appGroupHeader(
                                    group: group,
                                    isUserInApp: isUserInApp(group.bundleId, currentActivity: currentUserActivity)
                                )

                                ForEach(group.friends) { presence in
                                    FriendRow(
                                        presence: presence,
                                        onTap: { showFriendDetail(presence) },
                                        onNudge: { nudge(presence) },
                                        onRemove: { friendToRemove = presence },
                                        currentUserActivity: currentUserActivity
                                    )
                                    .focusable()
                                }
                            }
                        }

                        // Offline friends section
                        if !presenceListener.offlineFriends.isEmpty {
                            offlineSectionHeader

                            ForEach(presenceListener.offlineFriends) { presence in
                                FriendRow(
                                    presence: presence,
                                    onTap: { showFriendDetail(presence) },
                                    onRemove: { friendToRemove = presence }
                                )
                                .focusable()
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove \(friendToRemove?.user.name ?? "friend")?",
            isPresented: Binding(
                get: { friendToRemove != nil },
                set: { if !$0 { friendToRemove = nil } }
            ),
            presenting: friendToRemove
        ) { presence in
            Button("Remove", role: .destructive) {
                friendToRemove = nil
                remove(presence)
            }
            Button("Cancel", role: .cancel) { friendToRemove = nil }
        } message: { _ in
            Text("You will no longer see each other's activity.")
        }
        // Note: PresenceListener lifecycle is owned by AppDelegate
    }

    // MARK: - Section Headers

    @ViewBuilder
    private func appGroupHeader(group: AppGroup, isUserInApp: Bool) -> some View {
        HStack(spacing: 6) {
            // App icon
            AppIconView(iconData: group.appIcon, size: CGSize(width: 14, height: 14))

            // App name with count
            Text("\(group.appName)")
                .font(.caption2.weight(.semibold))
                .foregroundColor(isUserInApp ? .green : .secondary)
                .accessibilityLabel("\(group.appName) group")

            Text("(\(group.friends.count))")
                .font(.caption2.weight(.medium))
                .foregroundColor(isUserInApp ? .green.opacity(0.8) : .secondary.opacity(0.7))

            // "You're here" indicator
            if isUserInApp {
                HStack(spacing: 2) {
                    Image(systemName: "sparkle")
                        .font(.caption2)
                    Text("You're here")
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.15))
                )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isUserInApp
                ? Color.green.opacity(0.05)
                : Color.clear
        )
    }

    private var offlineSectionHeader: some View {
        Text("Offline")
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityLabel("Offline friends")
    }
}