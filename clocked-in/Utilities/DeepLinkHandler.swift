import Foundation
import OSLog

extension Notification.Name {
    /// Posted for `clockedin://add/{username}`. userInfo: ["username": String] (raw,
    /// unsanitised — observers must validate). Raw value "openAddFriend".
    nonisolated static let openAddFriend = Notification.Name("openAddFriend")
}

class DeepLinkHandler {
    static let shared = DeepLinkHandler()

    /// Posted when a deep link requests adding a friend. userInfo: ["username": String]
    /// (Same name as `Notification.Name.openAddFriend`.)
    static let addFriendNotification = Notification.Name.openAddFriend
    /// Posted when a deep link contains an invite code. userInfo: ["code": String]
    static let inviteCodeNotification = Notification.Name("DeepLinkInviteCode")

    /// Set to true by the auth flow right before it opens the browser for OAuth, and
    /// cleared when the callback is consumed. `clockedin://auth` links are ignored
    /// unless this is set (prevents login-CSRF / token injection via crafted links).
    static var isAwaitingOAuth = false

    private let log = Logger(subsystem: "com.clockedin", category: "DeepLinkHandler")

    private init() {}

    func handle(url: URL) {
        guard url.scheme?.lowercased() == "clockedin" else { return }

        switch url.host?.lowercased() {
        case "add":
            // clockedin://add/username
            if let username = url.pathComponents.dropFirst().first, !username.isEmpty {
                handleAddFriend(username: username)
            }
        case "invite":
            // clockedin://invite/CODE123
            if let code = url.pathComponents.dropFirst().first, !code.isEmpty {
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
        // Cap length defensively; NotchViewModel sanitises further before use.
        let trimmed = String(username.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        guard !trimmed.isEmpty else { return }
        log.info("Add friend request for username: \(trimmed, privacy: .private)")
        NotificationCenter.default.post(
            name: .openAddFriend,
            object: nil,
            userInfo: ["username": trimmed]
        )
    }

    private func handleInviteCode(code: String) {
        log.info("Invite code received")
        NotificationCenter.default.post(
            name: Self.inviteCodeNotification,
            object: nil,
            userInfo: ["code": code]
        )
        // Invite codes aren't redeemable in v1; at least open Add Friend.
        NotificationCenter.default.post(name: .openAddFriend, object: nil, userInfo: nil)
    }

    private func handleAuthCallback(url: URL) {
        guard Self.isAwaitingOAuth else {
            log.warning("Ignoring unsolicited clockedin://auth callback")
            return
        }
        Self.isAwaitingOAuth = false

        // OAuth callback: clockedin://auth?token=xxx&user_id=yyy
        Task { @MainActor in
            await AuthManager.shared.handleAuthCallback(url: url)
        }
    }
}
