import SwiftUI

struct PendingRequestsView: View {
    @State private var pendingRequests: [FriendRequest] = []
    @State private var isLoading = false
    @State private var error: AppError?
    @State private var actionError: AppError?
    @State private var processingRequestId: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            // Error banner
            if let error = error {
                ErrorBanner(
                    error: error,
                    onRetry: { Task { await loadRequests() } },
                    onDismiss: { self.error = nil }
                )
                .padding(.horizontal, 4)
            }

            // Action error (inline toast for accept/decline failures)
            if let actionError = actionError {
                ErrorBanner(
                    error: actionError,
                    onDismiss: { self.actionError = nil },
                    isCompact: true
                )
                .padding(.horizontal, 4)
            }

            // Requests list
            if isLoading && pendingRequests.isEmpty {
                ProgressView()
                    .padding()
            } else if pendingRequests.isEmpty && error == nil {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No pending requests")
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
            } else {
                List(pendingRequests) { request in
                    VStack(spacing: 12) {
                        HStack {
                            // Avatar
                            AvatarView(
                                avatarURL: request.fromAvatar,
                                displayName: request.fromName,
                                size: 40
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(request.fromName)
                                    .font(.headline)
                                Text("Sent \(request.createdAt.relativeTimeString())")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }

                        // Action buttons
                        HStack(spacing: 12) {
                            Button(action: { acceptRequest(request) }) {
                                Text("Accept")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                            .disabled(processingRequestId == request.id)
                            .accessibilityLabel("Accept request from \(request.fromName)")

                            Button(action: { declineRequest(request) }) {
                                Text("Decline")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.2))
                                    .foregroundColor(.primary)
                                    .cornerRadius(6)
                            }
                            .disabled(processingRequestId == request.id)
                            .accessibilityLabel("Decline request from \(request.fromName)")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listStyle(.plain)
            }
        }
        .task {
            await loadRequests()
        }
    }

    private func loadRequests() async {
        isLoading = true
        error = nil

        do {
            pendingRequests = try await FriendService.shared.getPendingRequests()
        } catch let err {
            error = AppError.from(err)
            ErrorHandler.shared.handle(err, context: "loadPendingRequests", showToUser: false)
        }

        isLoading = false
    }

    private func acceptRequest(_ request: FriendRequest) {
        Task {
            actionError = nil
            processingRequestId = request.id

            do {
                try await FriendService.shared.acceptRequest(request.id)
                pendingRequests.removeAll { $0.id == request.id }
            } catch let err {
                actionError = AppError.from(err)
                ErrorHandler.shared.handle(err, context: "acceptFriendRequest", showToUser: false)
            }

            processingRequestId = nil
        }
    }

    private func declineRequest(_ request: FriendRequest) {
        Task {
            actionError = nil
            processingRequestId = request.id

            do {
                try await FriendService.shared.declineRequest(request.id)
                pendingRequests.removeAll { $0.id == request.id }
            } catch let err {
                actionError = AppError.from(err)
                ErrorHandler.shared.handle(err, context: "declineFriendRequest", showToUser: false)
            }

            processingRequestId = nil
        }
    }

}