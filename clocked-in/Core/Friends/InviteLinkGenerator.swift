import Foundation
import AppKit

class InviteLinkGenerator {
    static let shared = InviteLinkGenerator()

    private init() {}

    func generateInviteLink(for username: String) -> String {
        return "clockedin://add/\(username)"
    }

    func copyInviteLinkToClipboard(for username: String) {
        let link = generateInviteLink(for: username)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    // Future: web link that redirects to deep link
    func generateWebInviteLink(for username: String) -> String {
        return "https://clocked-in.app/add/\(username)"
    }
}
