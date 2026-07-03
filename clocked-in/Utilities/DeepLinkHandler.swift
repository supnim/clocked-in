import Foundation
import OSLog

class DeepLinkHandler {
    static let shared = DeepLinkHandler()

    /// Posted when a deep link requests adding a friend. userInfo: ["username": String]
    static let addFriendNotification = Notification.Name("DeepLinkAddFriend")
    /// Posted when a deep link contains an invite code. userInfo: ["code": String]
    static let inviteCodeNotification = Notification.Name("DeepLinkInviteCode")

    private let log = Logger(subsystem: "com.clockedin", category: "DeepLinkHandler")

    private init() {}

    func handle(url: URL) {
        guard url.scheme == "clockedin" else { return }

        switch url.host {
        case "add":
            // clockedin://add/username
            if let username = url.pathComponents.dropFirst().first {
                handleAddFriend(username: username)
            }
        case "invite":
            // clockedin://invite/CODE123
            if let code = url.pathComponents.dropFirst().first {
                handleInviteCode(code: code)
            }
        case "auth":
            // clockedin://auth?token=xxx&user_id=yyy
            handleAuthCallback(url: url)
        default:
            break
        }
    }

    private func handleAddFriend(username: String) {
        log.info("Add friend request for username: \(username)")
        NotificationCenter.default.post(
            name: Self.addFriendNotification,
            object: nil,
            userInfo: ["username": username]
        )
    }

    private func handleInviteCode(code: String) {
        log.info("Invite code: \(code)")
        NotificationCenter.default.post(
            name: Self.inviteCodeNotification,
            object: nil,
            userInfo: ["code": code]
        )
    }

    private func handleAuthCallback(url: URL) {
        // OAuth callback: clockedin://auth?token=xxx&user_id=yyy
        Task { @MainActor in
            await AuthManager.shared.handleAuthCallback(url: url)
        }
    }
}