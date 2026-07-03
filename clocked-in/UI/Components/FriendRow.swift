import SwiftUI

struct FriendRow: View {
    let presence: FriendPresence
    var onTap: (() -> Void)? = nil
    var onNudge: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var timelineData: TimelineData? = nil

    /// Current user's activity for highlight comparison
    var currentUserActivity: Activity? = nil

    @State private var isHovered = false
    @State private var isExpanded = false

    /// Callback when expansion state changes (for notch height adjustment)
    var onExpansionChange: ((Bool) -> Void)? = nil

    /// Whether the current user is in the same app as this friend
    private var isInSameApp: Bool {
        guard let userActivity = currentUserActivity,
              let friendActivity = presence.currentActivity,
              !userActivity.bundleId.isEmpty,
              !friendActivity.bundleId.isEmpty else {
            return false
        }
        return userActivity.bundleId == friendActivity.bundleId
    }

    /// Highlight color when in same app
    private var sameAppHighlight: Color {
        Color.green.opacity(0.15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row content
            HStack(spacing: 8) {
                // Avatar - use avatarUrl from User model
                AvatarView(
                    avatarURL: presence.user.avatarUrl,
                    displayName: presence.user.name,
                    size: 32
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(presence.user.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)

                        PresenceIndicator(status: presence.status)

                        // Show "Together" badge when in same app
                        if isInSameApp {
                            workingTogetherBadge
                        }
                    }

                    // Status message (if set)
                    if let statusMessage = presence.user.statusMessage, !statusMessage.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "text.bubble")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                            Text(statusMessage)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let activity = presence.currentActivity {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                // App icon from Firebase
                                AppIconView(iconData: activity.appIcon, size: CGSize(width: 14, height: 14))

                                Text(activity.appName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                if let windowTitle = activity.windowTitle {
                                    Text(".")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(windowTitle)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            // Browser domain display
                            if let browserDomain = activity.browserDomain, !browserDomain.isEmpty {
                                Text(browserDomain)
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.accentColor.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    } else if presence.status == .offline {
                        Text("Last seen \(presence.lastSeen.relativeTimeString())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // "Currently with" display
                    if let currentlyWith = presence.currentlyWith, !currentlyWith.isEmpty {
                        currentlyWithView(names: currentlyWith)
                    }
                }

                Spacer()

                // Expand button (only show if timeline data available)
                if timelineData != nil {
                    expandButton
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                ZStack {
                    // Base background for same-app highlight
                    if isInSameApp {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(sameAppHighlight)
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    }
                    // Hover effect on top
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.05) : Color.clear)
                }
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                onTap?()
            }
            .accessibilityLabel("\(presence.user.name), \(presence.status.accessibilityDescription)")
            .contextMenu {
                Button("View Profile") { onTap?() }
                Button("Nudge") { onNudge?() }
                Divider()
                Button("Remove Friend", role: .destructive) { onRemove?() }
            }

            // Expanded content with timeline
            if isExpanded, let data = timelineData {
                expandedContent(data: data)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func currentlyWithView(names: [String]) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .font(.caption2)
                .foregroundColor(isInSameApp ? .green : .secondary)

            Text("Working with \(formatNames(names))")
                .font(.caption2.weight(isInSameApp ? .medium : .regular))
                .foregroundStyle(isInSameApp ? Color.green : Color.secondary)
                .lineLimit(1)
        }
        .padding(.top, 2)
    }

    /// Badge shown when user is in the same app as this friend
    @ViewBuilder
    private var workingTogetherBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.caption2)
            Text("Together")
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(.green)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.15))
        )
        .accessibilityLabel("Working together")
    }

    private var expandButton: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
            }
            onExpansionChange?(isExpanded)
        } label: {
            HStack(spacing: 2) {
                Text(isExpanded ? "Less" : "More")
                    .font(.caption2.weight(.medium))
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func expandedContent(data: TimelineData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Timeline bar
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's Activity")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)

                TimelineBar(data: data)
                    .frame(height: 20)
            }

            // Legend (top apps)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(data.apps.prefix(4), id: \.bundleId) { app in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(app.color)
                            .frame(width: 6, height: 6)

                        Text(app.appName)
                            .font(.caption2)
                            .lineLimit(1)

                        Spacer()

                        Text(app.formattedTime)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .padding(.leading, 40) // Indent to align with content after avatar
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.02))
        )
    }

    // MARK: - Helpers

    private func formatNames(_ names: [String]) -> String {
        switch names.count {
        case 1:
            return names[0]
        case 2:
            return "\(names[0]) & \(names[1])"
        case 3:
            return "\(names[0]), \(names[1]) & \(names[2])"
        default:
            let first = names.prefix(2).joined(separator: ", ")
            return "\(first) & \(names.count - 2) more"
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleUser = User(
        id: "1",
        username: "johndoe",
        statusMessage: "Focusing"
    )

    let sampleActivity = Activity(
        appName: "Xcode",
        bundleId: "com.apple.dt.Xcode",
        windowTitle: "MyProject - ViewController.swift",
        timestamp: Date()
    )

    let browserActivity = Activity(
        appName: "Safari",
        bundleId: "com.apple.Safari",
        windowTitle: "GitHub - clocked-in",
        browserDomain: "github.com",
        timestamp: Date()
    )

    // Current user is also in Xcode - for highlighting
    let currentUserActivity = Activity(
        appName: "Xcode",
        bundleId: "com.apple.dt.Xcode",
        timestamp: Date()
    )

    let sampleTimeline = TimelineData(
        apps: [
            AppTimelineEntry(appName: "Xcode", bundleId: "com.apple.dt.Xcode", totalTime: 7200, color: .blue, percentage: 0.4),
            AppTimelineEntry(appName: "Safari", bundleId: "com.apple.Safari", totalTime: 5400, color: .green, percentage: 0.3),
            AppTimelineEntry(appName: "Slack", bundleId: "com.tinyspeck.slackmacgap", totalTime: 3600, color: .purple, percentage: 0.2)
        ],
        totalTime: 16200,
        insights: []
    )

    VStack(spacing: 0) {
        // Online with activity - SAME APP as user (highlighted with "Together" badge)
        FriendRow(
            presence: FriendPresence(
                uid: "1",
                user: sampleUser,
                isOnline: true,
                currentActivity: sampleActivity,
                currentlyWith: ["Alice", "Carol"]
            ),
            timelineData: sampleTimeline,
            currentUserActivity: currentUserActivity
        )

        Divider().padding(.horizontal)

        // Online with browser domain - different app, with status
        FriendRow(
            presence: FriendPresence(
                uid: "2",
                user: User(id: "2", username: "janedoe", statusMessage: "In a meeting"),
                isOnline: true,
                currentActivity: browserActivity
            ),
            currentUserActivity: currentUserActivity
        )

        Divider().padding(.horizontal)

        // Online with "currently with" - different app
        FriendRow(
            presence: FriendPresence(
                uid: "3",
                user: User(id: "3", username: "mike"),
                isOnline: true,
                currentActivity: Activity(appName: "Figma", bundleId: "com.figma.Desktop", timestamp: Date()),
                currentlyWith: ["Sarah", "Alex"]
            ),
            currentUserActivity: currentUserActivity
        )

        Divider().padding(.horizontal)

        // Offline
        FriendRow(
            presence: FriendPresence(
                uid: "4",
                user: User(id: "4", username: "bob"),
                isOnline: false,
                lastSeen: Date().addingTimeInterval(-3600)
            )
        )
    }
    .frame(width: 320)
    .padding()
    .background(Color.black.opacity(0.8))
}