import Foundation
import SwiftUI

struct TimelineData {
    var apps: [AppTimelineEntry]
    var totalTime: TimeInterval
    var insights: [Insight]
}

struct AppTimelineEntry: Identifiable {
    let appName: String
    let bundleId: String
    let totalTime: TimeInterval
    let color: Color
    let percentage: Double

    var id: String { bundleId }

    var formattedTime: String {
        formatDuration(totalTime)
    }

    var formattedPercentage: String {
        String(format: "%.0f%%", percentage * 100)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}

enum TimelinePeriod: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
}

// MARK: - Insights

enum Insight: Identifiable {
    case moreTime(app: String, percent: Int)
    case lessTime(app: String, percent: Int)
    case newApp(app: String)
    case totalTime(hours: Double)

    var id: String {
        switch self {
        case .moreTime(let app, _): return "more_\(app)"
        case .lessTime(let app, _): return "less_\(app)"
        case .newApp(let app): return "new_\(app)"
        case .totalTime: return "total"
        }
    }

    var message: String {
        switch self {
        case .moreTime(let app, let percent):
            return "You spent \(percent)% more time in \(app) this week"
        case .lessTime(let app, let percent):
            return "You spent \(percent)% less time in \(app) this week"
        case .newApp(let app):
            return "New this week: \(app)"
        case .totalTime(let hours):
            return "You tracked \(String(format: "%.1f", hours)) hours this week"
        }
    }

    var icon: String {
        switch self {
        case .moreTime: return "arrow.up.circle.fill"
        case .lessTime: return "arrow.down.circle.fill"
        case .newApp: return "star.circle.fill"
        case .totalTime: return "clock.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .moreTime: return .green
        case .lessTime: return .orange
        case .newApp: return .blue
        case .totalTime: return .purple
        }
    }
}