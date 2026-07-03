import Foundation
import SwiftUI

struct NotchGeometry {
    let deviceNotchRect: CGRect
    let screenRect: CGRect
    let windowHeight: CGFloat
    let style: Style

    enum Style {
        case notch, floating
    }

    var notchScreenRect: CGRect {
        switch style {
        case .notch:
            return CGRect(
                x: screenRect.midX - deviceNotchRect.width / 2,
                y: screenRect.maxY - deviceNotchRect.height,
                width: deviceNotchRect.width,
                height: deviceNotchRect.height
            )
        case .floating:
            return CGRect(
                x: screenRect.midX - deviceNotchRect.width / 2,
                y: screenRect.maxY - deviceNotchRect.height - 10, // Float above the top
                width: deviceNotchRect.width,
                height: deviceNotchRect.height
            )
        }
    }

    func openedScreenRect(for size: CGSize) -> CGRect {
        let width = size.width - 6
        let height = size.height - 30
        let notchRect = notchScreenRect
        return CGRect(
            x: screenRect.midX - width / 2,
            y: notchRect.minY - height,
            width: width,
            height: height
        )
    }

    func isPointInNotch(_ point: CGPoint) -> Bool {
        notchScreenRect.insetBy(dx: -10, dy: -5).contains(point)
    }

    func isPointInOpenedPanel(_ point: CGPoint, size: CGSize) -> Bool {
        openedScreenRect(for: size).contains(point)
    }

    func isPointOutsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        !openedScreenRect(for: size).contains(point)
    }

    /// Calculate the hit test rect based on current status
    /// Used by PassThroughHostingView to determine click-through behavior
    static func calculateHitTestRect(status: NotchStatus, openedSize: CGSize, deviceNotchRect: CGRect, screenWidth: CGFloat, windowHeight: CGFloat) -> CGRect {
        switch status {
        case .opened:
            let panelWidth = openedSize.width + 52  // Add corner radius padding
            let panelHeight = openedSize.height
            return CGRect(
                x: (screenWidth - panelWidth) / 2,
                y: windowHeight - panelHeight,
                width: panelWidth,
                height: panelHeight
            )

        case .closed, .popping:
            return CGRect(
                x: (screenWidth - deviceNotchRect.width) / 2 - 10,  // ±10px horizontal
                y: windowHeight - deviceNotchRect.height - 5,        // +5px vertical
                width: deviceNotchRect.width + 20,
                height: deviceNotchRect.height + 10
            )
        }
    }

    static func create(for screen: NSScreen) -> NotchGeometry {
        if screen.hasNotch, let notchSize = screen.notchSize {
            return NotchGeometry(
                deviceNotchRect: CGRect(origin: .zero, size: notchSize),
                screenRect: screen.frame,
                windowHeight: screen.frame.height,
                style: .notch
            )
        } else {
            let defaultSize = CGSize(width: 200, height: 32)
            return NotchGeometry(
                deviceNotchRect: CGRect(origin: .zero, size: defaultSize),
                screenRect: screen.frame,
                windowHeight: screen.frame.height,
                style: .floating
            )
        }
    }
}

extension NSScreen {
    var hasNotch: Bool {
        guard let auxiliaryTopLeftArea = auxiliaryTopLeftArea,
              let auxiliaryTopRightArea = auxiliaryTopRightArea else {
            return false
        }
        // If there's a gap between left and right areas, there's a notch
        return auxiliaryTopRightArea.minX > auxiliaryTopLeftArea.maxX
    }

    var notchSize: CGSize? {
        guard hasNotch,
              let leftArea = auxiliaryTopLeftArea,
              let rightArea = auxiliaryTopRightArea else { return nil }

        let width = rightArea.minX - leftArea.maxX
        let height = max(leftArea.height, rightArea.height)
        return CGSize(width: width, height: height)
    }
}
