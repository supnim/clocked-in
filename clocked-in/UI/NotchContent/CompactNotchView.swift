import SwiftUI

struct CompactNotchView: View {
    private var onlineFriends: [FriendPresence] {
        PresenceListener.shared.friendsPresence.filter { $0.status != .offline }
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
        NetworkMonitor.shared.connectionState.isOffline
    }

    private var currentNotification: FriendActivityNotification? {
        NotchNotificationManager.shared.currentNotification
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
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
            }
            .opacity(onlineCount > 0 || showOfflineBanner ? 1.0 : 0.5)

            // Notification overlay - observes NotchNotificationManager
            if let notification = currentNotification {
                VStack {
                    Spacer()
                    AppChangeNotification(
                        friend: notification.friend,
                        oldAppIcon: notification.oldAppIcon,
                        newAppIcon: notification.newAppIcon
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentNotification != nil)
        .animation(.easeInOut(duration: 0.3), value: showOfflineBanner)
        .onAppear {
            PresenceListener.shared.startListening()
        }
        .onDisappear {
            PresenceListener.shared.stopListening()
        }
    }
}
