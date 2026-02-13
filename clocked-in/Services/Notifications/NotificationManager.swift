import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestPermission() async throws -> Bool {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        return granted
    }

    func send(title: String, body: String, userInfo: [AnyHashable: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                print("Error sending notification: \(error)")
            }
        }
    }

    func sendFriendOnline(_ friend: User) {
        send(
            title: "Friend Online",
            body: "\(friend.name) is now online",
            userInfo: ["type": "friend_online", "uid": friend.id ?? ""]
        )
    }

    func sendSameApp(_ friends: [FriendPresence], appName: String) {
        let names = friends.map { $0.user.name }
        let body = formatNames(names) + " in \(appName)"

        send(
            title: "Same App",
            body: body,
            userInfo: ["type": "same_app", "app": appName]
        )
    }

    private func formatNames(_ names: [String]) -> String {
        switch names.count {
        case 1:
            return names[0]
        case 2:
            return names.joined(separator: " and ")
        default:
            let firstPart = names.dropLast().joined(separator: ", ")
            return firstPart + ", and " + names.last!
        }
    }
}
