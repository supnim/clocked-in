import SwiftUI

struct AppChangeNotification: View {
    let friend: FriendPresence
    let oldAppIcon: Data?
    let newAppIcon: Data?
    var onTapFriend: ((FriendPresence) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            // Friend avatar (small)
            AvatarView(avatarURL: friend.user.avatarUrl, displayName: friend.user.name, size: 20)

            // Old app icon with arrow
            if let oldIcon = oldAppIcon {
                AppIconView(iconData: oldIcon, size: CGSize(width: 16, height: 16))
            }

            // Arrow
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.secondary)

            // New app icon
            if let newIcon = newAppIcon {
                AppIconView(iconData: newIcon, size: CGSize(width: 16, height: 16))
            }

            // Friend name
            Text(friend.user.username)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .accessibilityLabel("\(friend.user.username) switched apps")
        .onTapGesture {
            onTapFriend?(friend)
        }
    }
}