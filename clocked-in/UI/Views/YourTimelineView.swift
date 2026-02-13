import SwiftUI

struct YourTimelineView: View {
    let onEditStatus: () -> Void

    @State private var selectedPeriod: TimelinePeriod = .today
    @State private var timelineData: TimelineData?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Activity")
                        .font(.system(size: 16, weight: .semibold))

                    Text("See how you spend your time")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onEditStatus) {
                    Text("Edit Status")
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
            }

            // Period selector
            HStack(spacing: 0) {
                ForEach(TimelinePeriod.allCases, id: \.self) { period in
                    Button(action: { selectPeriod(period) }) {
                        Text(period.rawValue)
                            .font(.system(size: 12, weight: selectedPeriod == period ? .semibold : .regular))
                            .foregroundColor(selectedPeriod == period ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                }
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)

            // Content area
            ZStack {
                if isLoading {
                    LoadingView()
                } else if let error = errorMessage {
                    ErrorView(message: error, onRetry: loadTimeline)
                } else if let data = timelineData {
                    TimelineContentView(data: data)
                } else {
                    EmptyTimelineView(onLoad: loadTimeline)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
        .padding(16)
        .onAppear {
            loadTimeline()
        }
        .onChange(of: selectedPeriod) { oldValue, newValue in
            loadTimeline()
        }
    }

    private func selectPeriod(_ period: TimelinePeriod) {
        selectedPeriod = period
    }

    private func loadTimeline() {
        guard let userId = AuthManager.shared.currentUser?.id else {
            errorMessage = "Please sign in to view your timeline"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let data = try await TimelineService.shared.getTimeline(for: userId, period: selectedPeriod)

                await MainActor.run {
                    self.timelineData = data
                    self.isLoading = false
                }
            } catch let error as TimelineError {
                await MainActor.run {
                    self.errorMessage = error.errorDescription ?? "Failed to load timeline"
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading your activity...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text("Unable to load timeline")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onRetry) {
                Text("Try Again")
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }
        }
    }
}

struct EmptyTimelineView: View {
    let onLoad: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No activity data yet")
                .font(.system(size: 14))
            Text("Start using apps to see your timeline")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onLoad) {
                Text("Refresh")
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }
        }
    }
}

struct TimelineContentView: View {
    let data: TimelineData

    var body: some View {
        VStack(spacing: 12) {
            // Timeline bar
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 24)
                .overlay(
                    Text("Timeline visualization")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                )

            // Stats
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Time")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(formatTotalTime(data.totalTime))
                        .font(.system(size: 14, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Top App")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let topApp = data.apps.first {
                        Text(topApp.appName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                    }
                }

                Spacer()
            }

            // App breakdown
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's Apps")
                    .font(.system(size: 12, weight: .semibold))

                ForEach(data.apps.prefix(3), id: \.bundleId) { app in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(app.color)
                            .frame(width: 8, height: 8)

                        Text(app.appName)
                            .font(.system(size: 12))
                            .lineLimit(1)

                        Spacer()

                        Text(app.formattedTime)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Insights
            if !data.insights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("💡 Insights")
                        .font(.system(size: 12, weight: .semibold))

                    ForEach(data.insights) { insight in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: insight.icon)
                                .foregroundColor(insight.color)
                                .font(.system(size: 10))

                            Text(insight.message)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private func formatTotalTime(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}