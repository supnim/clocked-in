import Foundation

extension Date {
    /// Returns a human-readable relative time string (e.g., "5 minutes ago", "2 hours ago")
    func relativeTimeString() -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: self, to: now)

        if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "just now"
        }
    }
}
