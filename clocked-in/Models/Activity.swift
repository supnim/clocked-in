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

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case bundleId = "bundle_id"
        case windowTitle = "window_title"
        case browserURL = "browser_url"
        case browserDomain = "browser_domain"
        case browserTitle = "browser_title"
        case appIcon = "app_icon"
        case timestamp
    }

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

    enum CodingKeys: String, CodingKey {
        case id
        case appName = "app_name"
        case bundleId = "bundle_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case windowTitles = "window_titles"
        case browserDomains = "browser_domains"
    }

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

    enum CodingKeys: String, CodingKey {
        case id, date, apps
        case totalTime = "total_time"
    }
}

struct AppSummary: Codable {
    let appName: String
    let bundleId: String
    var totalTime: TimeInterval
    var sessionCount: Int

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case bundleId = "bundle_id"
        case totalTime = "total_time"
        case sessionCount = "session_count"
    }
}