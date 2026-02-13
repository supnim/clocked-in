import Foundation

class DeepLinkHandler {
    static let shared = DeepLinkHandler()

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
        // Show add friend confirmation
        // This would post a notification or update app state
        print("Add friend request for username: \(username)")
    }

    private func handleInviteCode(code: String) {
        // Handle invite codes (future feature)
        print("Invite code: \(code)")
    }

    private func handleAuthCallback(url: URL) {
        // OAuth callback: clockedin://auth?token=xxx&user_id=yyy
        Task { @MainActor in
            await AuthManager.shared.handleAuthCallback(url: url)
        }
    }
}