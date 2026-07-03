import XCTest

@testable import clocked_in

@MainActor
final class NotchViewModelTests: XCTestCase {
    private func makeViewModel() -> NotchViewModel {
        let geometry = NotchGeometry(
            deviceNotchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
            screenRect: CGRect(x: 0, y: 0, width: 1440, height: 900),
            windowHeight: 900,
            style: .floating
        )
        // installMonitors: false — avoid installing real global NSEvent monitors
        // and deep-link observers for a view model that only exists for this test.
        return NotchViewModel(geometry: geometry, installMonitors: false)
    }

    func testInitialStateIsClosed() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.status, .closed)
    }

    func testNotchOpenTransitionsToOpenedAndRecordsReason() {
        let viewModel = makeViewModel()
        viewModel.notchOpen(reason: .click)
        XCTAssertEqual(viewModel.status, .opened)
        XCTAssertEqual(viewModel.openReason, .click)
    }

    func testNotchCloseReturnsToClosed() {
        let viewModel = makeViewModel()
        viewModel.notchOpen(reason: .hover)
        viewModel.notchClose()
        XCTAssertEqual(viewModel.status, .closed)
    }

    func testNotchQuickPopEntersPoppingStateWithNotification() {
        let viewModel = makeViewModel()
        let friend = FriendPresence(
            uid: "friend-1",
            user: User(id: "friend-1", username: "testfriend"),
            isOnline: true,
            lastSeen: Date(),
            currentActivity: nil,
            currentlyWith: nil
        )
        let notification = FriendActivityNotification(
            friend: friend,
            oldApp: nil,
            newApp: "Xcode",
            oldAppIcon: nil,
            newAppIcon: nil,
            timestamp: Date()
        )

        viewModel.notchQuickPop(notification: notification)

        XCTAssertEqual(viewModel.status, .popping)
        XCTAssertEqual(viewModel.quickPopNotification, notification)
    }
}
