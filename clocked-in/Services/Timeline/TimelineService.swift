import Foundation
import SwiftUI
import OSLog

enum TimelineError: LocalizedError {
    case noDataAvailable
    case networkError(Error)
    case dataProcessingError(String)
    case invalidPeriod
    case userNotFound

    var errorDescription: String? {
        switch self {
        case .noDataAvailable:
            return "No activity data available for this period"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .dataProcessingError(let message):
            return "Data processing error: \(message)"
        case .invalidPeriod:
            return "Invalid time period selected"
        case .userNotFound:
            return "User data not found"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noDataAvailable:
            return "Try a different time period or check back later"
        case .networkError:
            return "Check your internet connection and try again"
        case .dataProcessingError:
            return "Try refreshing the timeline"
        case .invalidPeriod:
            return "Select a valid time period"
        case .userNotFound:
            return "Please log in again"
        }
    }
}

class TimelineService {
    static let shared = TimelineService()

    private let logger = Logger(subsystem: "com.clockedin", category: "TimelineService")

    private init() {}

    /// Gets timeline data for a user and period with error handling
    func getTimeline(for uid: String, period: TimelinePeriod) async throws -> TimelineData {
        let calendar = Calendar.current
        let now = Date()

        let (startDate, endDate): (Date, Date) = {
            switch period {
            case .today:
                return (calendar.startOfDay(for: now), now)
            case .week:
                let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
                return (weekStart, now)
            case .month:
                let monthStart = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: now))!
                return (monthStart, now)
            }
        }()

        logger.debug("Fetching timeline for \(period.rawValue) from \(startDate) to \(endDate)")

        // TODO: Implement ActivityService for session retrieval
        // For now, return empty timeline
        let sessions: [ActivitySession] = []
        let summaries: [DailySummary] = []

        // Aggregate into timeline data
        let timelineData = aggregateTimeline(sessions: sessions, summaries: summaries)

        // Generate insights
        let previousPeriodData = try await getPreviousPeriodData(for: uid, currentPeriod: period)
        let insights = generateInsights(current: timelineData, previous: previousPeriodData)

        return TimelineData(
            apps: timelineData.apps,
            totalTime: timelineData.totalTime,
            insights: insights
        )
    }

    /// Gets daily summaries for a date range
    private func getSummaries(for uid: String, from startDate: Date, to endDate: Date) async throws -> [DailySummary] {
        // TODO: Implement summary querying
        // For now, return empty array
        return []
    }

    /// Gets data for the previous period for comparison
    private func getPreviousPeriodData(for uid: String, currentPeriod: TimelinePeriod) async throws -> TimelineData? {
        let calendar = Calendar.current
        let now = Date()

        let (startDate, endDate): (Date, Date) = {
            switch currentPeriod {
            case .today:
                let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
                return (calendar.startOfDay(for: yesterday), calendar.startOfDay(for: now))
            case .week:
                let twoWeeksAgo = calendar.date(byAdding: .day, value: -13, to: now)!
                let oneWeekAgo = calendar.date(byAdding: .day, value: -6, to: now)!
                return (twoWeeksAgo, oneWeekAgo)
            case .month:
                let twoMonthsAgo = calendar.date(byAdding: .day, value: -59, to: now)!
                let oneMonthAgo = calendar.date(byAdding: .day, value: -29, to: now)!
                return (twoMonthsAgo, oneMonthAgo)
            }
        }()

        // TODO: Implement ActivityService for session retrieval
        let sessions: [ActivitySession] = []
        return aggregateTimeline(sessions: sessions, summaries: [])
    }

    /// Aggregates sessions and summaries into timeline data
    private func aggregateTimeline(sessions: [ActivitySession], summaries: [DailySummary]) -> TimelineData {
        var appTimes: [String: (name: String, time: TimeInterval)] = [:]

        // Add session times
        for session in sessions {
            let duration = session.duration
            if duration > 0 {
                let existing = appTimes[session.bundleId] ?? (name: session.appName, time: 0)
                appTimes[session.bundleId] = (existing.name, existing.time + duration)
            }
        }

        // Add summary times
        for summary in summaries {
            for app in summary.apps {
                let existing = appTimes[app.bundleId] ?? (name: app.appName, time: 0)
                appTimes[app.bundleId] = (existing.name, existing.time + app.totalTime)
            }
        }

        let totalTime = appTimes.values.reduce(0) { $0 + $1.time }

        let apps = appTimes.map { bundleId, data in
            AppTimelineEntry(
                appName: data.name,
                bundleId: bundleId,
                totalTime: data.time,
                color: colorForBundleId(bundleId),
                percentage: totalTime > 0 ? data.time / totalTime : 0
            )
        }.sorted { $0.totalTime > $1.totalTime }

        return TimelineData(apps: apps, totalTime: totalTime, insights: [])
    }

    /// Generates stable colors for bundle IDs
    private func colorForBundleId(_ bundleId: String) -> Color {
        // Create stable hash
        var hasher = Hasher()
        hasher.combine(bundleId)
        let hash = abs(hasher.finalize())

        // Map to hue (0-360)
        let hue = Double(hash % 360) / 360.0

        // Fixed saturation and brightness for consistency
        return Color(hue: hue, saturation: 0.65, brightness: 0.75)
    }

    /// Generates insights by comparing current and previous periods
    private func generateInsights(current: TimelineData, previous: TimelineData?) -> [Insight] {
        var insights: [Insight] = []

        guard let previous = previous else {
            // First period, show total time
            if current.totalTime > 0 {
                let hours = current.totalTime / 3600
                insights.append(.totalTime(hours: hours))
            }
            return insights
        }

        // Compare app times
        for app in current.apps {
            if let prevApp = previous.apps.first(where: { $0.bundleId == app.bundleId }) {
                let change = (app.totalTime - prevApp.totalTime) / max(prevApp.totalTime, 1) // Avoid division by zero
                if change > 0.25 { // > 25% increase
                    insights.append(.moreTime(app: app.appName, percent: Int(change * 100)))
                } else if change < -0.25 { // > 25% decrease
                    insights.append(.lessTime(app: app.appName, percent: Int(abs(change) * 100)))
                }
            } else {
                // New app
                insights.append(.newApp(app: app.appName))
            }
        }

        // Limit to 3 insights
        return Array(insights.prefix(3))
    }
}