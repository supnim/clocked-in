import Foundation

class BrowserURLFetcher {
    enum BrowserType {
        case safari, chrome, arc, firefox, edge
    }

    static func getCurrentURL(for bundleId: String) -> String? {
        guard let browserType = browserTypeFromBundleId(bundleId) else { return nil }
        return getURLViaAppleScript(browserType)
    }

    private static func browserTypeFromBundleId(_ bundleId: String) -> BrowserType? {
        switch bundleId {
        case "com.apple.Safari": return .safari
        case "com.google.Chrome": return .chrome
        case "company.thebrowser.Browser": return .arc // Arc browser
        case "com.microsoft.edgemac": return .edge
        default: return nil
        }
    }

    private static func getURLViaAppleScript(_ browserType: BrowserType) -> String? {
        // Skip Firefox as it doesn't support AppleScript
        if browserType == .firefox { return nil }

        let scriptSource: String
        switch browserType {
        case .safari:
            scriptSource = """
            tell application "Safari"
                return URL of current tab of front window
            end tell
            """
        case .chrome:
            scriptSource = """
            tell application "Google Chrome"
                return URL of active tab of front window
            end tell
            """
        case .arc:
            scriptSource = """
            tell application "Arc"
                return URL of active tab of front window
            end tell
            """
        case .edge:
            scriptSource = """
            tell application "Microsoft Edge"
                return URL of active tab of front window
            end tell
            """
        case .firefox:
            return nil // Firefox doesn't support AppleScript
        }

        guard let script = NSAppleScript(source: scriptSource) else { return nil }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error = error {
            print("AppleScript error: \(error)")
            return nil
        }

        return result.stringValue
    }
}