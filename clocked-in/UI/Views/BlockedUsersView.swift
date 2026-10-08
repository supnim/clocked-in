import SwiftUI

/// Lists blocked users with an Unblock action. Presented as a sheet from Settings.
struct BlockedUsersView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var blockedUsers: [BlockedUser] = []
    @State private var isLoading = false
    @State private var error: AppError?
    @State private var processingId: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Blocked Users")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("Blocked users can't find you, send you friend requests, nudge you or see your activity.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let error {
                ErrorBanner(
                    error: error,
                    onRetry: { Task { await load() } },
                    onDismiss: { self.error = nil },
                    isCompact: true
                )
            }

            Divider()

            if isLoading && blockedUsers.isEmpty {
                ProgressView()
                    .padding()
            } else if blockedUsers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "hand.raised")
                        .font(.title3)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No blocked users")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(blockedUsers, id: \.id) { user in
                            row(for: user)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 300, minHeight: 350)
        .task {
            await load()
        }
    }

    private func displayName(for user: BlockedUser) -> String {
        if let name = user.displayName, !name.isEmpty { return name }
        if let username = user.username, !username.isEmpty { return username }
        return "Unknown user"
    }

    private func row(for user: BlockedUser) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: user))
                    .font(.subheadline.weight(.medium))
                if let username = user.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button("Unblock") { unblock(user) }
                .controlSize(.small)
                .disabled(processingId == user.id)
                .accessibilityLabel("Unblock \(displayName(for: user))")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            blockedUsers = try await FriendService.shared.getBlockedUsers()
        } catch let err {
            error = AppError.from(err)
            ErrorHandler.shared.handle(err, context: "listBlockedUsers", showToUser: false)
        }
        isLoading = false
    }

    private func unblock(_ user: BlockedUser) {
        processingId = user.id
        error = nil
        Task {
            do {
                try await FriendService.shared.unblockUser(user.id)
                blockedUsers.removeAll { $0.id == user.id }
            } catch let err {
                error = AppError.from(err)
                ErrorHandler.shared.handle(err, context: "unblockUser", showToUser: false)
            }
            processingId = nil
        }
    }
}
