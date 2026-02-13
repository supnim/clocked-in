import SwiftUI

struct AddFriendView: View {
    @State private var searchQuery = ""
    @State private var searchResults: [User] = []
    @State private var isSearching = false
    @State private var searchError: AppError?
    @State private var requestError: AppError?
    @State private var successMessage: String?
    @State private var inviteLink: String = ""
    @State private var searchTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    /// Whether network is available for searches
    private var isOnline: Bool {
        !NetworkMonitor.shared.connectionState.isOffline
    }

    var body: some View {
        VStack(spacing: 12) {
            // Offline banner
            if !isOnline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 11))
                    Text("Search unavailable offline")
                        .font(.system(size: 11))
                }
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search by username", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .disabled(!isOnline)
                    .onChange(of: searchQuery) { _, newValue in
                        searchUsers(query: newValue)
                    }
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .opacity(isOnline ? 1 : 0.5)

            // Search results
            if isSearching {
                ProgressView()
                    .padding()
            } else if !searchResults.isEmpty {
                List(searchResults) { user in
                    HStack {
                        // Avatar
                        AvatarView(
                            avatarURL: user.avatarUrl,
                            displayName: user.name,
                            size: 32
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name)
                                .font(.system(size: 14, weight: .medium))
                            Text("@\(user.username)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Add") {
                            sendFriendRequest(to: user)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!isOnline)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            } else if !searchQuery.isEmpty && !isSearching {
                Text("No users found")
                    .foregroundColor(.secondary)
                    .padding()
            }

            // Share link section
            VStack(spacing: 6) {
                Text("Or share your invite link")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                HStack {
                    Text(inviteLink.isEmpty ? "Loading..." : inviteLink)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(inviteLink.isEmpty ? .secondary.opacity(0.5) : .secondary)
                        .lineLimit(1)

                    Spacer()

                    Button(action: {
                        if let user = AuthManager.shared.currentUser, !user.username.isEmpty {
                            InviteLinkGenerator.shared.copyInviteLinkToClipboard(for: user.username)
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .disabled(inviteLink.isEmpty)
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
            }

            // Error and success messages
            if let error = searchError {
                ErrorBanner(
                    error: error,
                    onRetry: { searchUsers(query: searchQuery) },
                    onDismiss: { searchError = nil },
                    isCompact: true
                )
            }

            if let error = requestError {
                ErrorBanner(
                    error: error,
                    onDismiss: { requestError = nil },
                    isCompact: true
                )
            }

            if let message = successMessage {
                InlineErrorText(message: message, isSuccess: true)
            }
        }
        .padding(.horizontal, 4)
        .task {
            await loadInviteLink()
        }
    }

    private func searchUsers(query: String) {
        // Cancel previous search task (debouncing)
        searchTask?.cancel()

        guard isOnline else {
            searchError = .network(message: "Search unavailable while offline")
            return
        }

        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        searchError = nil
        successMessage = nil

        // Debounce: wait 300ms before making API call
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            await MainActor.run { isSearching = true }

            do {
                let results = try await UsernameService.shared.searchUsers(query: query)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchError = AppError.from(error)
                    searchResults = []
                    isSearching = false
                    ErrorHandler.shared.handle(error, context: "searchUsers", showToUser: false)
                }
            }
        }
    }

    private func sendFriendRequest(to user: User) {
        guard isOnline else {
            requestError = .network(message: "Cannot send requests while offline")
            return
        }

        requestError = nil
        successMessage = nil

        Task {
            do {
                try await FriendService.shared.sendFriendRequest(to: user.username)
                successMessage = "Friend request sent to @\(user.username)!"

                // Clear success message after a few seconds
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    if successMessage?.contains(user.username) == true {
                        successMessage = nil
                    }
                }
            } catch let err {
                let appError = AppError.from(err)

                // Handle specific cases
                if case .api(let code, _) = appError, code == 409 {
                    requestError = .validation(message: "Friend request already sent")
                } else {
                    requestError = appError
                }

                ErrorHandler.shared.handle(err, context: "sendFriendRequest", showToUser: false)
            }
        }
    }

    private func loadInviteLink() async {
        if let user = AuthManager.shared.currentUser {
            let username = user.username
            if !username.isEmpty {
                inviteLink = InviteLinkGenerator.shared.generateInviteLink(for: username)
            }
        }
    }
}
