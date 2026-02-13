import SwiftUI

struct PendingRequestsView: View {
    @State private var pendingRequests: [FriendRequest] = []
    @State private var isLoading = false
    @State private var error: AppError?
    @State private var actionError: AppError?
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
                            if let avatarURL = request.fromAvatar,
                               let url = URL(string: avatarURL) {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                } placeholder: {
                                    Circle().fill(Color.blue.opacity(0.3))
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.blue.opacity(0.3))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(request.fromName.prefix(1).uppercased())
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(request.fromName)
                                    .font(.system(size: 16, weight: .medium))
                                Text("Sent \(relativeTimeString(from: request.createdAt))")
                                    .font(.system(size: 12))
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
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }

                            Button(action: { declineRequest(request) }) {
                                Text("Decline")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.2))
                                    .foregroundColor(.primary)
                                    .cornerRadius(6)
                            }
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

            do {
                try await FriendService.shared.acceptRequest(request.id)
                // Remove from local array
                pendingRequests.removeAll { $0.id == request.id }
            } catch let err {
                actionError = AppError.from(err)
                ErrorHandler.shared.handle(err, context: "acceptFriendRequest", showToUser: false)
            }
        }
    }

    private func declineRequest(_ request: FriendRequest) {
        Task {
            actionError = nil

            do {
                try await FriendService.shared.declineRequest(request.id)
                // Remove from local array
                pendingRequests.removeAll { $0.id == request.id }
            } catch let err {
                actionError = AppError.from(err)
                ErrorHandler.shared.handle(err, context: "declineFriendRequest", showToUser: false)
            }
        }
    }

    private func relativeTimeString(from date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)

        if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "just now"
        }
    }
}