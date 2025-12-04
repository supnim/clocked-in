//
//  StatusBarRenderer.swift
//  clocked-in
//
//  Created by Nimesh on 04/12/2025.
//

import AppKit
import SwiftUI

/// Renders visual progress indicators for the menu bar status item
@MainActor
struct StatusBarRenderer {
    private static let menuBarHeight: CGFloat = 22
    private static let iconSize: CGFloat = 18
    private static let barWidth: CGFloat = 32
    private static let barHeight: CGFloat = 10

    // MARK: - Public Rendering Methods

    /// Renders the appropriate visual based on current settings
    static func render(
        percentage: Int,
        mode: ViewMode,
        settings: AppSettings,
        isOvertime: Bool = false
    ) -> (image: NSImage?, title: String?) {
        switch settings.displayStyle {
        case .text:
            return (nil, formatTextDisplay(percentage: percentage, mode: mode, settings: settings, isOvertime: isOvertime))
        case .pie:
            let image = renderPieChart(percentage: percentage, isOvertime: isOvertime)
            let label = visualLabel(percentage: percentage, settings: settings, isOvertime: isOvertime)
            return (image, label)
        case .bar:
            let image = renderProgressBar(percentage: percentage, isOvertime: isOvertime)
            let label = visualLabel(percentage: percentage, settings: settings, isOvertime: isOvertime)
            return (image, label)
        case .gauge:
            let image = renderGauge(percentage: percentage, isOvertime: isOvertime)
            let label = visualLabel(percentage: percentage, settings: settings, isOvertime: isOvertime)
            return (image, label)
        }
    }

    // MARK: - Text Display

    private static func formatTextDisplay(
        percentage: Int,
        mode: ViewMode,
        settings: AppSettings,
        isOvertime: Bool
    ) -> String {
        if isOvertime {
            return "Overtime"
        }

        let percentageText = "\(percentage)%"

        switch settings.textDetail {
        case .full:
            return "\(mode.rawValue) \(percentageText)"
        case .compact:
            let icon: String
            switch mode {
            case .day: icon = "D"
            case .week: icon = "W"
            case .month: icon = "M"
            case .year: icon = "Y"
            }
            return "\(icon) \(percentageText)"
        case .minimal:
            return percentageText
        }
    }

    // MARK: - Visual Label

    private static func visualLabel(
        percentage: Int,
        settings: AppSettings,
        isOvertime: Bool
    ) -> String? {
        switch settings.visualDetail {
        case .withPercent:
            return isOvertime ? "OT" : "\(percentage)%"
        case .visualOnly:
            return nil
        }
    }

    // MARK: - Pie Chart Rendering

    private static func renderPieChart(percentage: Int, isOvertime: Bool) -> NSImage {
        let size = NSSize(width: iconSize, height: iconSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2 - 1

            // Background circle
            let bgPath = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            NSColor.tertiaryLabelColor.setFill()
            bgPath.fill()

            // Progress arc
            if percentage > 0 || isOvertime {
                let progress = isOvertime ? 1.0 : Double(min(percentage, 100)) / 100.0
                let startAngle: CGFloat = 90
                let endAngle = startAngle - (360 * progress)

                let progressPath = NSBezierPath()
                progressPath.move(to: center)
                progressPath.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: true
                )
                progressPath.close()

                let fillColor = isOvertime ? NSColor.systemOrange : AppSettings.shared.accentColor.nsColor
                fillColor.setFill()
                progressPath.fill()
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    // MARK: - Progress Bar Rendering

    private static func renderProgressBar(percentage: Int, isOvertime: Bool) -> NSImage {
        let size = NSSize(width: barWidth, height: barHeight)
        let image = NSImage(size: size, flipped: false) { rect in
            let cornerRadius: CGFloat = 3

            // Background
            let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.tertiaryLabelColor.setFill()
            bgPath.fill()

            // Progress fill
            let progress = isOvertime ? 1.0 : Double(min(percentage, 100)) / 100.0
            if progress > 0 {
                let fillWidth = (rect.width - 2) * progress
                let fillRect = NSRect(x: 1, y: 1, width: fillWidth, height: rect.height - 2)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius - 1, yRadius: cornerRadius - 1)

                let fillColor = isOvertime ? NSColor.systemOrange : AppSettings.shared.accentColor.nsColor
                fillColor.setFill()
                fillPath.fill()
            }

            // Border
            let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.secondaryLabelColor.setStroke()
            borderPath.lineWidth = 0.5
            borderPath.stroke()

            return true
        }

        image.isTemplate = false
        return image
    }

    // MARK: - Gauge Rendering

    private static func renderGauge(percentage: Int, isOvertime: Bool) -> NSImage {
        let size = NSSize(width: iconSize, height: iconSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2 - 2
            let lineWidth: CGFloat = 2.5

            // Background arc (270 degrees, from bottom-left to bottom-right)
            let bgPath = NSBezierPath()
            bgPath.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 225,
                endAngle: -45,
                clockwise: true
            )
            bgPath.lineWidth = lineWidth
            bgPath.lineCapStyle = .round
            NSColor.tertiaryLabelColor.setStroke()
            bgPath.stroke()

            // Progress arc
            let progress = isOvertime ? 1.0 : Double(min(percentage, 100)) / 100.0
            if progress > 0 {
                let progressAngle = 225 - (270 * progress)
                let progressPath = NSBezierPath()
                progressPath.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 225,
                    endAngle: progressAngle,
                    clockwise: true
                )
                progressPath.lineWidth = lineWidth
                progressPath.lineCapStyle = .round

                let strokeColor = isOvertime ? NSColor.systemOrange : AppSettings.shared.accentColor.nsColor
                strokeColor.setStroke()
                progressPath.stroke()
            }

            return true
        }

        image.isTemplate = false
        return image
    }
}
