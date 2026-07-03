import SwiftUI
import AppKit

struct EmptyStateView: View {
    let viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Illustration
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }

            // Text content
            VStack(spacing: 8) {
                Text("No friends yet")
                    .font(.title3.weight(.semibold))

                Text("Connect with friends to see what they're working on in real-time")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }

            // Action buttons
            VStack(spacing: 12) {
                Button(action: { viewModel.showContent(.addFriend) }) {
                    HStack {
                        Image(systemName: "person.badge.plus")
                        Text("Add Friends")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .accessibilityLabel("Add friends")

                Button(action: shareInviteLink) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Invite Link")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                .accessibilityLabel("Share invite link")
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.vertical, 32)
    }

    private func shareInviteLink() {
        Task {
            guard let user = AuthManager.shared.currentUser else { return }
            let username = user.username
            guard !username.isEmpty else { return }

            let inviteLink = InviteLinkGenerator.shared.generateInviteLink(for: username)

            // Share using system share sheet
            let shareItems = [inviteLink]
            let activityVC = NSSharingServicePicker(items: shareItems)

            // Find the main window to present from
            if let window = NSApplication.shared.windows.first,
               let contentView = window.contentView {
                activityVC.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
            }
        }
    }
}
