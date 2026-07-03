import SwiftUI

/// Conditionally applies Liquid Glass effect on macOS 26+
struct GlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content
        }
    }
}

struct ActionButton: View {
    let icon: String
    var label: String? = nil
    let action: () -> Void
    @State private var isHovered = false

    /// Maps SF Symbol names to human-readable labels
    private var resolvedLabel: String {
        if let label { return label }
        switch icon {
        case "xmark": return "Close"
        case "gear": return "Settings"
        case "bell": return "Notifications"
        case "person.badge.plus": return "Add Friend"
        case "chevron.left": return "Back"
        default: return icon.replacingOccurrences(of: ".", with: " ")
        }
    }

    var body: some View {
        Button(action: action) {
            buttonContent
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(resolvedLabel)
        .accessibilityHint("Double-click to activate")
    }

    private var buttonContent: some View {
        Image(systemName: icon)
            .font(.caption)
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
            .modifier(GlassEffectModifier())
    }
}