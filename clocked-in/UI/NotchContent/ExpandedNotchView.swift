import SwiftUI

struct ExpandedNotchView: View {
    let viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.contentType {
            case .usernamePicker:
                UsernamePickerView(
                    onComplete: { viewModel.onUsernameSetupComplete() }
                )

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
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .frame(maxHeight: 200)
                    .task {
                        try? await Task.sleep(for: .seconds(1))
                        if PresenceListener.shared.friendsPresence.first(where: { $0.uid == friendUid }) == nil {
                            viewModel.showContent(.lobby)
                        }
                    }
                }
            }
        }
    }
}