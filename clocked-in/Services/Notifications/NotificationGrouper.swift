import Foundation

@MainActor
class NotificationGrouper {
    static let shared = NotificationGrouper()

    private var pendingSameAppNotifications: [String: [FriendPresence]] = [:]
    private var debounceTask: Task<Void, Never>?

    private init() {}

    func friendChangedApp(_ friend: FriendPresence, myCurrentApp: String) {
        guard friend.currentActivity?.appName == myCurrentApp else { return }

        // Group by app name
        pendingSameAppNotifications[myCurrentApp, default: []].append(friend)

        // Debounce to group multiple friends
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            self.sendGroupedNotification()
        }
    }

    private func sendGroupedNotification() {
        for (appName, friends) in pendingSameAppNotifications {
            NotificationManager.shared.sendSameApp(friends, appName: appName)
        }
        pendingSameAppNotifications.removeAll()
    }
}
