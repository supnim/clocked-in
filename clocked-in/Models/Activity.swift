import Foundation

struct Activity: Codable, Hashable {
    var appName: String
    var bundleId: String
    var windowTitle: String?
    var browserURL: String?
    var browserDomain: String?
    var browserTitle: String?
    var appIcon: Data?
    var timestamp: Date

    init(appName: String, bundleId: String, windowTitle: String? = nil, browserURL: String? = nil, browserDomain: String? = nil, browserTitle: String? = nil, appIcon: Data? = nil, timestamp: Date = Date()) {
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.browserURL = browserURL
        self.browserDomain = browserDomain
        self.browserTitle = browserTitle
        self.appIcon = appIcon
        self.timestamp = timestamp
    }
}

// MARK: - Activity Session

struct ActivitySession: Codable, Identifiable {
    var id: String?
    let appName: String
    let bundleId: String
    let startTime: Date
    var endTime: Date?
    var windowTitles: [String]?
    var browserDomains: [String]?

    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }
}

// MARK: - Daily Summary

struct DailySummary: Codable, Identifiable {
    var id: String?     // Format: "YYYY-MM-DD"
    let date: String
    var apps: [AppSummary]
    var totalTime: TimeInterval
}

struct AppSummary: Codable {
    let appName: String
    let bundleId: String
    var totalTime: TimeInterval
    var sessionCount: Int
}