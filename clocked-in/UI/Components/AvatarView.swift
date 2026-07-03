import SwiftUI

/// Reusable avatar component that displays user profile images or fallback initials
struct AvatarView: View {
    let avatarURL: String?
    let displayName: String
    let size: CGFloat

    var body: some View {
        if let avatarURL = avatarURL,
           let url = URL(string: avatarURL) {
            AsyncImage(url: url) { image in
                image.resizable()
            } placeholder: {
                Circle().fill(Color.accentColor.opacity(0.3))
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityLabel("Avatar for \(displayName)")
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: size, height: size)
                .overlay(
                    Text(displayName.prefix(1).uppercased())
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundColor(.white)
                )
                .accessibilityLabel("Avatar for \(displayName)")
        }
    }
}
