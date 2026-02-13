import SwiftUI

struct NotchContentView: View {
    @Bindable var viewModel: NotchViewModel
    @State private var isHovering = false

    private let cornerRadiusInsets = (
        opened: (top: CGFloat(19), bottom: CGFloat(24)),
        closed: (top: CGFloat(6), bottom: CGFloat(14))
    )

    private var closedNotchSize: CGSize {
        viewModel.geometry.deviceNotchRect.size
    }

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed, .popping:
            return closedNotchSize
        case .opened:
            return viewModel.openedSize
        }
    }

    private var topCornerRadius: CGFloat {
        viewModel.status == .opened ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        viewModel.status == .opened ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                notchLayout
                    .frame(maxWidth: viewModel.status == .opened ? notchSize.width : nil, alignment: .top)
                    .padding(.horizontal, viewModel.status == .opened ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.bottom)
                    .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
                    .background(Color.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: (viewModel.status == .opened || isHovering) ? Color.black.opacity(0.7) : .clear,
                        radius: 6
                    )
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        maxHeight: viewModel.status == .opened ? notchSize.height : nil,
                        alignment: .top
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.status)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                            isHovering = hovering
                        }
                    }
                    .onTapGesture {
                        if viewModel.status != .opened {
                            viewModel.notchOpen(reason: .click)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private var headerTitle: String {
        switch viewModel.contentType {
        case .usernamePicker: return "Setup"
        case .lobby: return "Friends"
        case .settings: return "Settings"
        case .addFriend: return "Add Friend"
        case .pendingRequests: return "Friend Requests"
        case .friendDetail: return "Friend Details"
        }
    }

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .frame(height: max(24, closedNotchSize.height))

            if viewModel.status == .opened {
                ExpandedNotchView(viewModel: viewModel)
                    .frame(width: notchSize.width - 24)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            if viewModel.status == .opened {
                HStack(spacing: 8) {
                    Text(headerTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    if viewModel.contentType != .lobby {
                        ActionButton(icon: "chevron.left") {
                            viewModel.showContent(.lobby)
                        }
                    } else {
                        ActionButton(icon: "person.badge.plus") {
                            viewModel.showContent(.addFriend)
                        }

                        ActionButton(icon: "bell") {
                            viewModel.showContent(.pendingRequests)
                        }

                        ActionButton(icon: "gear") {
                            viewModel.showContent(.settings)
                        }
                    }

                    ActionButton(icon: "xmark") {
                        viewModel.notchClose()
                    }
                }
                .padding(.horizontal, 8)
            } else {
                CompactNotchView()
                    .frame(width: closedNotchSize.width, height: closedNotchSize.height)
            }
        }
        .frame(height: closedNotchSize.height)
    }
}
