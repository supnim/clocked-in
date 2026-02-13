import AppKit
import Combine
import SwiftUI

enum NotchStatus {
    case closed, opened, popping
}

enum NotchOpenReason {
    case click, hover, notification, boot
}

@MainActor
@Observable
class NotchViewModel {
    var status: NotchStatus = .closed
    var openReason: NotchOpenReason = .boot
    var contentType: NotchContentType = .lobby
    var isHovering = false

    @ObservationIgnored
    var onStatusChange: ((NotchStatus) -> Void)?

    private let events = EventMonitors.shared
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: DispatchWorkItem?
    private var bootAnimationTimer: DispatchWorkItem?
    private let hoverDelay: TimeInterval = 1.0

    let geometry: NotchGeometry

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        setupEventHandlers()
    }

    // Dynamic height support
    var isExpanded: Bool = false

    var openedSize: CGSize {
        let baseWidth = min(geometry.screenRect.width * 0.4, 480)
        let baseHeight: CGFloat = switch contentType {
        case .usernamePicker: 280
        case .lobby: isExpanded ? 800 : 320  // Expandable lobby
        case .settings: 420
        case .addFriend: 400
        case .pendingRequests: 360
        case .friendDetail: 360
        }

        return CGSize(width: baseWidth, height: baseHeight)
    }

    private func setupEventHandlers() {
        events.mouseLocation
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in
                self?.handleMouseMove(location)
            }
            .store(in: &cancellables)

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleMouseDown()
            }
            .store(in: &cancellables)
    }

    private func handleMouseMove(_ location: CGPoint) {
        let inNotch = geometry.isPointInNotch(location)
        let inOpened = status == .opened && geometry.isPointInOpenedPanel(location, size: openedSize)
        let newHovering = inNotch || inOpened

        guard newHovering != isHovering else { return }
        isHovering = newHovering

        hoverTimer?.cancel()
        hoverTimer = nil

        if isHovering && (status == .closed || status == .popping) {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.isHovering else { return }
                self.notchOpen(reason: .hover)
            }
            hoverTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: workItem)
        }
    }

    private     func handleMouseDown() {
        let location = NSEvent.mouseLocation

        switch status {
        case .opened:
            // Prevent closing if username picker is shown and no username set
            if contentType == .usernamePicker {
                // Don't close the notch when username picker is active
                return
            }

            if geometry.isPointOutsidePanel(location, size: openedSize) {
                notchClose()
                repostClickAt(location)
            } else if geometry.notchScreenRect.contains(location) {
                notchClose()
            }
        case .closed, .popping:
            if geometry.isPointInNotch(location) {
                notchOpen(reason: .click)
            }
        }
    }

    private func repostClickAt(_ location: CGPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let screen = NSScreen.main else { return }
            let screenHeight = screen.frame.height
            let cgPoint = CGPoint(x: location.x, y: screenHeight - location.y)

            if let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseDown.post(tap: .cghidEventTap)
            }

            if let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - State Transitions

    // MARK: - Animation Constants (matched to claude-island)
    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    private let popAnimation = Animation.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)
    private let bootDuration: TimeInterval = 1.0

    func notchOpen(reason: NotchOpenReason) {
        openReason = reason
        withAnimation(openAnimation) {
            status = .opened
        }
        onStatusChange?(status)
    }

    func notchClose() {
        withAnimation(closeAnimation) {
            status = .closed
        }
        onStatusChange?(status)
    }

    func notchPop() {
        withAnimation(popAnimation) {
            status = .popping
        }
        onStatusChange?(status)

        bootAnimationTimer?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.notchClose()
        }
        bootAnimationTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + bootDuration, execute: workItem)
    }

    func notchUnpop() {
        guard status == .popping else { return }
        bootAnimationTimer?.cancel()
        bootAnimationTimer = nil
        status = .closed
        onStatusChange?(status)
    }

    func showContent(_ type: NotchContentType) {
        contentType = type
        if status == .closed {
            notchOpen(reason: .click)
        }
    }

    // MARK: - Username Setup

    func initializeContentType() {
        // Check if user has completed username setup
        if needsUsernameSetup() {
            contentType = .usernamePicker
            // Auto-open on first launch
            if status == .closed {
                notchOpen(reason: .boot)
            }
        } else {
            contentType = .lobby
        }
    }

    func onUsernameSetupComplete() {
        // Called when username setup is finished
        contentType = .lobby
        if status == .opened {
            notchClose()
        }
    }

    // MARK: - Dynamic Height

    func toggleExpanded() {
        guard contentType == .lobby && status == .opened else { return }
        isExpanded.toggle()

        // Animate the size change
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            // Size will be recalculated via openedSize
        }
    }

    var expandButtonTitle: String {
        isExpanded ? "▲ Less" : "▼ More"
    }

    private func needsUsernameSetup() -> Bool {
        // Check if user has authenticated and has a username set
        guard let user = AuthManager.shared.currentUser else {
            return false // Not authenticated, will show onboarding instead
        }
        // If username is empty or default (e.g., UUID-based), show username picker
        return user.username.isEmpty
    }
}
