import SwiftUI

struct CompactNotchView: View {
    let viewModel: NotchViewModel
    let presenceListener: PresenceListener
    let networkMonitor: NetworkMonitor
    let notificationManager: NotchNotificationManager

    private var onlineFriends: [FriendPresence] {
        presenceListener.friendsPresence.filter { $0.status != .offline }
    }

    private var onlineCount: Int {
        onlineFriends.count
    }

    private var displayStatus: PresenceStatus {
        if onlineFriends.isEmpty {
            return .offline
        }
        // Show online if any friend is online, otherwise away
        return onlineFriends.contains(where: { $0.status == .online }) ? .online : .away
    }

    /// Whether to show offline/reconnecting banner
    private var showOfflineBanner: Bool {
        networkMonitor.connectionState.isOffline
    }

    private var currentNotification: FriendActivityNotification? {
        notificationManager.currentNotification
    }

    var body: some View {
        ZStack {
            // Main content
            HStack(spacing: 4) {
                // Offline/reconnecting indicator (using new OfflineBanner)
                if showOfflineBanner {
                    OfflineBanner(isCompact: true)
                } else {
                    // Online friends indicator
                    PresenceIndicator(status: displayStatus)

                    if onlineCount > 0 {
                        Text("\(onlineCount)")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white)
                    }
                }
            }
            .opacity(onlineCount > 0 || showOfflineBanner ? 1.0 : 0.5)

            // Quick-pop notification overlay
            if let quickPop = viewModel.quickPopNotification {
                HStack(spacing: 6) {
                    Text(quickPop.friend.user.username)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                    if let newApp = quickPop.newApp {
                        Text("→ \(newApp)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .transition(.opacity)
            }

            // Notification overlay - observes NotchNotificationManager
            if let notification = currentNotification {
                VStack {
                    Spacer()
                    AppChangeNotification(
                        friend: notification.friend,
                        oldAppIcon: notification.oldAppIcon,
                        newAppIcon: notification.newAppIcon,
                        onTapFriend: { friend in
                            viewModel.showContent(.friendDetail(friend.uid))
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentNotification != nil)
        .animation(.easeInOut(duration: 0.2), value: viewModel.quickPopNotification != nil)
        .animation(.easeInOut(duration: 0.3), value: showOfflineBanner)
        .onAppear {
            presenceListener.startListening()
        }
        .onDisappear {
            presenceListener.stopListening()
        }
    }
}
