import SwiftUI

struct ExpandedNotchView: View {
    let viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.contentType {
            case .usernamePicker:
                VStack(spacing: 12) {
                    Text("Welcome to Clocked-In")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Pick your username to get started")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Continue →")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .padding(16)
                .frame(maxHeight: 200)

            case .lobby:
                LobbyView(viewModel: viewModel)
                    .padding(8)

            case .settings:
                SettingsView()
                    .padding(8)

            case .addFriend:
                AddFriendView()
                    .padding(8)

            case .pendingRequests:
                PendingRequestsView()
                    .padding(8)

            case .friendDetail(let friendUid):
                if let friendPresence = PresenceListener.shared.friendsPresence.first(where: { $0.uid == friendUid }) {
                    FriendDetailView(friendPresence: friendPresence)
                        .padding(8)
                } else {
                    VStack(spacing: 12) {
                        Text("Friend not found")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .frame(maxHeight: 200)
                }
            }
        }
    }
}