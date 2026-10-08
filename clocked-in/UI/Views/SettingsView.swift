import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable private var authManager = AuthManager.shared
    @Bindable private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingHiddenApps = false
    @State private var showingStatusPicker = false
    @State private var showingBlockedUsers = false

    // Launch at login mirrors SMAppService.mainApp.status (source of truth)
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginMessage: String?

    // Account actions
    @State private var showSignOutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var accountError: AppError?

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

                        Toggle("Hide your activity from friends", isOn: $appSettings.isInvisible)
                            .font(.body)
                            .help("Invisible mode: friends see you as offline and nothing is shared")

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

                        Toggle("Launch at Login", isOn: Binding(
                            get: { launchAtLoginEnabled },
                            set: { setLaunchAtLogin($0) }
                        ))
                            .font(.body)
                            .help("Start Clocked-In at login")

                        if let message = launchAtLoginMessage {
                            HStack(spacing: 6) {
                                Text(message)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                if SMAppService.mainApp.status == .requiresApproval {
                                    Button("Open Login Items") {
                                        SMAppService.openSystemSettingsLoginItems()
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                    .onAppear {
                        launchAtLoginEnabled = LaunchAtLogin.isEnabled
                    }

                    Divider()

                    // About section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        Link(destination: AppLinks.privacyPolicy) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Link(destination: AppLinks.support) {
                            Label("Support", systemImage: "questionmark.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Divider()

                    // Account section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Account")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        Button(action: { showingBlockedUsers = true }) {
                            HStack {
                                Text("Blocked Users")
                                    .font(.body.weight(.medium))
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showingBlockedUsers) {
                            BlockedUsersView()
                        }

                        if let error = accountError {
                            ErrorBanner(
                                error: error,
                                onDismiss: { accountError = nil },
                                isCompact: true
                            )
                        }

                        Button(action: { showSignOutConfirmation = true }) {
                            Text("Sign Out")
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeletingAccount)
                        .confirmationDialog("Sign out of Clocked-In?", isPresented: $showSignOutConfirmation) {
                            Button("Sign Out", role: .destructive) { signOut() }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("You'll stop sharing your activity until you sign back in. Your account stays tied to this Mac.")
                        }

                        Button(action: { showDeleteConfirmation = true }) {
                            HStack(spacing: 6) {
                                if isDeletingAccount {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isDeletingAccount ? "Deleting Account…" : "Delete Account…")
                                    .foregroundColor(.red)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeletingAccount)
                        .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirmation) {
                            Button("Delete Account", role: .destructive) { deleteAccount() }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This permanently deletes your account, username, friends and friend requests from Clocked-In's servers. This can't be undone.")
                        }
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

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginMessage = nil
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            launchAtLoginMessage = error.localizedDescription
        }
        // Always re-read the real status so the toggle reverts on failure
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
        appSettings.launchAtLogin = launchAtLoginEnabled
        if enabled && SMAppService.mainApp.status == .requiresApproval {
            launchAtLoginMessage = "Approve Clocked-In in System Settings › General › Login Items."
        }
    }

    private func signOut() {
        authManager.signOut()
        dismiss()
    }

    private func deleteAccount() {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        accountError = nil

        Task {
            do {
                try await authManager.deleteAccount()
                isDeletingAccount = false
                dismiss()
            } catch let err {
                isDeletingAccount = false
                accountError = AppError.from(err)
                ErrorHandler.shared.handle(err, context: "deleteAccount", showToUser: false)
            }
        }
    }
}
