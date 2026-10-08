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

