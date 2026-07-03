import SwiftUI

struct SettingsView: View {
    @Bindable private var authManager = AuthManager.shared
    @Bindable private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingHiddenApps = false
    @State private var showingStatusPicker = false

    var body: some View {
        ScrollView {
                VStack(spacing: 20) {

                    // Profile section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Profile")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        if let user = authManager.currentUser {
                            HStack(spacing: 12) {
                                // Avatar
                                AvatarView(
                                    avatarURL: user.avatarUrl,
                                    displayName: user.name,
                                    size: 48
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(user.name)
                                        .font(.headline)
                                    Text("@\(user.username)")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                        }

                        // Custom status
                        Button(action: { showingStatusPicker = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "text.bubble")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let status = authManager.currentUser?.statusMessage {
                                    Text(status)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                } else {
                                    Text("Set a status...")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                    .sheet(isPresented: $showingStatusPicker) {
                        StatusPickerView()
                    }

                    Divider()

                    // Privacy section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Privacy & Sharing")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        Toggle("Invisible Mode", isOn: $appSettings.isInvisible)
                            .font(.body)
                            .help("Hide your activity from all friends")

                        Toggle("Share Window Titles", isOn: $appSettings.shareWindowTitle)
                            .font(.body)
                            .help("Show window titles to friends")

                        Toggle("Share Browser URLs", isOn: $appSettings.shareBrowserURL)
                            .font(.body)
                            .help("Show browser URLs to friends")

                        // Hidden apps section
                        Button(action: { showingHiddenApps = true }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text("Hidden Apps")
                                            .font(.body.weight(.medium))
                                            .foregroundColor(.primary)

                                        if !appSettings.hiddenApps.isEmpty {
                                            Text("(\(appSettings.hiddenApps.count))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Text("Apps you don't want to share activity from")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .sheet(isPresented: $showingHiddenApps) {
                        HiddenAppsManagerView()
                            .frame(minWidth: 300, minHeight: 350)
                    }

                    Divider()

                    // Nudge section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.wave.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("Nudges")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                        }

                        Toggle(isOn: $appSettings.nudgeShake) {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Shake Screen")
                            }
                        }
                        .font(.body)
                        .help("Shake screen when nudged")

                        Toggle(isOn: $appSettings.nudgeSound) {
                            HStack(spacing: 6) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Play Sound")
                            }
                        }
                        .font(.body)
                        .help("Play sound when nudged")

                        Toggle(isOn: $appSettings.nudgeNotification) {
                            HStack(spacing: 6) {
                                Image(systemName: "bell.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Show Notification")
                            }
                        }
                        .font(.body)
                        .help("Show notification when nudged")
                    }

                    Divider()

                    // General section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("General")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        Toggle("Launch at Login", isOn: $appSettings.launchAtLogin)
                            .font(.body)
                            .help("Start Clocked-In at login")
                    }

                    Divider()

                    // Link Account section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Link Account")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        Text("Link a sign-in provider to secure your account")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: signInWithGoogle) {
                            HStack {
                                Image(systemName: "g.circle.fill")
                                    .font(.title3)
                                Text("Link Google Account")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: signInWithApple) {
                            HStack {
                                Image(systemName: "apple.logo")
                                    .font(.title3)
                                Text("Link Apple Account")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()

                    // Account section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Account")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        Button(action: signOut) {
                            Text("Sign Out")
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()

                    Section {
                        Button("Quit Clocked-In") {
                            NSApp.terminate(nil)
                        }
                        .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 4)
        }
    }

    private func signInWithGoogle() {
        AuthManager.shared.signInWithGoogle()
    }

    private func signInWithApple() {
        Task {
            do {
                try await AuthManager.shared.signInWithApple()
            } catch {
                // Silently handle - user cancelled or error
            }
        }
    }

    private func signOut() {
        Task {
            authManager.signOut()
            dismiss()
        }
    }
}
