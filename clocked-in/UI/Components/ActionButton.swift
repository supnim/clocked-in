import SwiftUI

struct ActionButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isHovered ? .primary.opacity(0.9) : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isHovered ? Color.white.opacity(0.15) : Color.white.opacity(0.1))
                        .overlay(
                            Circle()
                                .stroke(isHovered ? Color.white.opacity(0.3) : Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}