

import Foundation
import SwiftUI
import AppKit
import Combine

// MARK: - NotchPanel (NSPanel subclass for proper floating behavior)

class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        // Panel-specific configuration
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false

        // Allows tooltips when app is inactive
        allowsToolTipsWhenApplicationIsInactive = true
    }
}

// MARK: - NotchWindowController

class NotchWindowController: NSWindowController {
    private let viewModel: NotchViewModel
    private var cancellables = Set<AnyCancellable>()

    /// The window height for positioning (matches claude-island)
    private let windowHeight: CGFloat = 750

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel

        let screenFrame = viewModel.geometry.screenRect

        // Create NSPanel (not NSWindow) for proper floating behavior
        let panel = NotchPanel(
            contentRect: NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.maxY - windowHeight,
                width: screenFrame.width,
                height: windowHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Window configuration (matched to claude-island)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false  // SwiftUI handles shadow
        panel.isMovable = false  // Prevents movement during space switches
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true  // Default: clicks pass through

        // Set up content with pass-through hosting view
        let hostingView = PassThroughHostingView(rootView: NotchContentView(viewModel: viewModel))
        let capturedWindowHeight = windowHeight
        hostingView.hitTestRect = { [weak viewModel] in
            guard let vm = viewModel else { return .zero }
            return NotchGeometry.calculateHitTestRect(
                status: vm.status,
                openedSize: vm.openedSize,
                deviceNotchRect: vm.geometry.deviceNotchRect,
                screenWidth: vm.geometry.screenRect.width,
                windowHeight: capturedWindowHeight
            )
        }
        panel.contentView = hostingView

        super.init(window: panel)

        // Subscribe to status changes for dynamic mouse event handling
        setupStatusObserver()

        // Boot animation after slight delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.viewModel.notchPop()
        }
    }

    private func setupStatusObserver() {
        viewModel.onStatusChange = { [weak self] status in
            guard let self = self, let panel = self.window as? NotchPanel else { return }

            DispatchQueue.main.async {
                switch status {
                case .opened:
                    // Enable mouse events when opened
                    panel.ignoresMouseEvents = false

                    // Only activate if NOT opened by notification
                    if self.viewModel.openReason != .notification {
                        NSApp.activate(ignoringOtherApps: false)
                        panel.makeKey()
                    }

                case .closed, .popping:
                    // Disable mouse events when closed (clicks pass through)
                    panel.ignoresMouseEvents = true
                }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}

// MARK: - PassThroughHostingView (Click-through with dynamic hit testing)

class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    /// Closure that returns the current hit-testable rect
    var hitTestRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only accept hits within the dynamic panel rect
        guard hitTestRect().contains(point) else {
            return nil  // Pass through to windows behind
        }
        return super.hitTest(point)
    }
}
