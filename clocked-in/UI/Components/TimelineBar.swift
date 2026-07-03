import SwiftUI

struct TimelineBar: View {
    let data: TimelineData
    let height: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(data.apps.prefix(10), id: \.bundleId) { app in
                    Rectangle()
                        .fill(app.color)
                        .frame(width: max(1, geometry.size.width * app.percentage)) // Ensure minimum width
                }

                // "Other" category if more than 10 apps
                if data.apps.count > 10 {
                    let otherPercentage = data.apps.dropFirst(10).reduce(0) { $0 + $1.percentage }
                    Rectangle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: max(1, geometry.size.width * otherPercentage))
                }
            }
        }
        .frame(height: height)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
}

struct TimelineLegend: View {
    let data: TimelineData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(data.apps.prefix(8), id: \.bundleId) { app in
                HStack(spacing: 8) {
                    Circle()
                        .fill(app.color)
                        .frame(width: 8, height: 8)

                    Text(app.appName)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()

                    Text(app.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if data.apps.count > 8 {
                let remaining = data.apps.dropFirst(8)
                let otherTime = remaining.reduce(0) { $0 + $1.totalTime }

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 8, height: 8)

                    Text("Other")
                        .font(.caption)

                    Spacer()

                    Text(formatDuration(otherTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
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

struct TimelineInsightsView: View {
    let insights: [Insight]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "lightbulb")
                    .font(.subheadline.weight(.semibold))
                Text("Insights")
                    .font(.subheadline.weight(.semibold))
            }

            ForEach(insights) { insight in
                HStack(spacing: 8) {
                    Image(systemName: insight.icon)
                        .foregroundColor(insight.color)
                        .font(.caption)

                    Text(insight.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            if insights.isEmpty {
                Text("Keep using Clocked-In to see insights about your activity patterns!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

#Preview {
    let sampleData = TimelineData(
        apps: [
            AppTimelineEntry(appName: "Xcode", bundleId: "com.apple.dt.Xcode", totalTime: 7200, color: .blue, percentage: 0.4),
            AppTimelineEntry(appName: "Safari", bundleId: "com.apple.Safari", totalTime: 5400, color: .green, percentage: 0.3),
            AppTimelineEntry(appName: "Slack", bundleId: "com.tinyspeck.slackmacgap", totalTime: 3600, color: .purple, percentage: 0.2),
            AppTimelineEntry(appName: "Mail", bundleId: "com.apple.mail", totalTime: 1800, color: .orange, percentage: 0.1)
        ],
        totalTime: 18000,
        insights: [
            .moreTime(app: "Xcode", percent: 25),
            .newApp(app: "Figma")
        ]
    )

    VStack(spacing: 16) {
        TimelineBar(data: sampleData)
            .frame(width: 300)

        TimelineLegend(data: sampleData)

        TimelineInsightsView(insights: sampleData.insights)
    }
    .padding()
}