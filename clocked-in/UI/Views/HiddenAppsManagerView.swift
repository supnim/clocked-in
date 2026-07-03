import SwiftUI
import AppKit

/// Represents an installed app for display in the hidden apps manager
struct InstalledApp: Identifiable, Hashable {
    let id: String  // bundleId
    let name: String
    let bundleId: String
    let icon: NSImage?

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleId)
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.bundleId == rhs.bundleId
    }
}

struct HiddenAppsManagerView: View {
    @Bindable private var appSettings = AppSettings.shared
    @State private var recentApps: [InstalledApp] = []
    @State private var manualBundleId: String = ""
    @State private var showingAddSection = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Hidden Apps")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddSection.toggle() }) {
                    Image(systemName: showingAddSection ? "minus.circle" : "plus.circle")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help(showingAddSection ? "Close add section" : "Add hidden app")
            }

            // Description
            Text("Activity from these apps will appear as \"ghost\" status to your friends.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Add App Section (collapsible)
            if showingAddSection {
                addAppSection
            }

            Divider()

            // Hidden Apps List
            if appSettings.hiddenApps.isEmpty {
                emptyState
            } else {
                hiddenAppsList
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .task {
            loadRecentApps()
        }
    }

    // MARK: - Add App Section

    private var addAppSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Recent Apps Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent Apps")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                if recentApps.isEmpty {
                    Text("No recent apps found")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                        .italic()
                        .padding(.vertical, 4)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentApps.filter { !appSettings.isAppHidden($0.bundleId) }) { app in
                                recentAppButton(app)
                            }
                        }
                    }
                }
            }

            // Manual Entry
            VStack(alignment: .leading, spacing: 6) {
                Text("Manual Entry")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("Bundle ID (e.g., com.apple.Safari)", text: $manualBundleId)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .padding(6)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)

                    Button(action: addManualBundleId) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(manualBundleId.isEmpty)
                }
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    private func recentAppButton(_ app: InstalledApp) -> some View {
        Button(action: { hideApp(app) }) {
            VStack(spacing: 4) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                }
                Text(app.name)
                    .font(.system(size: 9))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(width: 50)
            }
            .padding(6)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("Hide \(app.name)")
    }

    // MARK: - Hidden Apps List

    private var hiddenAppsList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(appSettings.hiddenApps, id: \.self) { bundleId in
                    hiddenAppRow(bundleId: bundleId)
                }
            }
        }
    }

    private func hiddenAppRow(bundleId: String) -> some View {
        let appInfo = getAppInfo(for: bundleId)

        return HStack(spacing: 10) {
            // App Icon
            if let icon = appInfo?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }

            // App Name & Bundle ID
            VStack(alignment: .leading, spacing: 2) {
                Text(appInfo?.name ?? "Unknown App")
                    .font(.subheadline.weight(.medium))
                Text(bundleId)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Remove Button
            Button(action: { unhideApp(bundleId) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show activity from this app")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.title3)
                .foregroundColor(.secondary.opacity(0.5))

            Text("No hidden apps")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Add apps above to hide their activity")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Actions

    private func hideApp(_ app: InstalledApp) {
        appSettings.hideApp(app.bundleId)
    }

    private func unhideApp(_ bundleId: String) {
        appSettings.unhideApp(bundleId)
    }

    private func addManualBundleId() {
        let trimmed = manualBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appSettings.hideApp(trimmed)
        manualBundleId = ""
    }

    // MARK: - Data Loading

    private func loadRecentApps() {
        let runningApps = NSWorkspace.shared.runningApplications
        var apps: [InstalledApp] = []

        for app in runningApps {
            guard let bundleId = app.bundleIdentifier,
                  let name = app.localizedName,
                  app.activationPolicy == .regular else { continue }

            // Skip system apps we don't want to show
            let systemBundleIds = [
                "com.apple.finder",
                "com.apple.dock",
                "com.apple.SystemUIServer",
                "com.apple.loginwindow",
                "com.apple.WindowManager"
            ]
            guard !systemBundleIds.contains(bundleId) else { continue }

            let installedApp = InstalledApp(
                id: bundleId,
                name: name,
                bundleId: bundleId,
                icon: app.icon
            )
            apps.append(installedApp)
        }

        // Sort by name
        recentApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func getAppInfo(for bundleId: String) -> InstalledApp? {
        // First check running apps
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            return InstalledApp(
                id: bundleId,
                name: runningApp.localizedName ?? bundleId,
                bundleId: bundleId,
                icon: runningApp.icon
            )
        }

        // Try to find the app bundle
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let bundle = Bundle(url: appURL)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? appURL.deletingPathExtension().lastPathComponent

            let icon = NSWorkspace.shared.icon(forFile: appURL.path)

            return InstalledApp(
                id: bundleId,
                name: name,
                bundleId: bundleId,
                icon: icon
            )
        }

        return nil
    }
}

#Preview {
    HiddenAppsManagerView()
        .frame(width: 300, height: 400)
}
