import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @State private var authError: AppError?
    @State private var isRegistering = false
    @State private var isRegistered = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo/Title
            VStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Clocked-In")
                    .font(.title2.bold())

                Text("See what your friends are working on in real-time")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if isRegistering {
                ProgressView("Setting up...")
            } else if isRegistered {
                // Show username picker after device registration
                UsernamePickerView(onComplete: completeSetup)
            }

            // Error display
            if let error = authError {
                ErrorBanner(
                    error: error,
                    onDismiss: { authError = nil }
                )
                .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding()
        .frame(width: 320, height: 480)
        .task {
            await registerDevice()
        }
    }

    private func registerDevice() async {
        isRegistering = true
        do {
            try await AuthManager.shared.signInWithDevice()
            isRegistered = true
        } catch {
            authError = AppError.from(error)
        }
        isRegistering = false
    }

    private func completeSetup() {
        AppSettings.shared.hasCompletedOnboarding = true
    }
}

struct UsernameSetupView: View {
    @Binding var username: String
    @State private var isCheckingAvailability = false
    @State private var claimError: AppError?
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Choose a username")
                .font(.title3.weight(.semibold))

            Text("This will be your unique identifier for friend requests")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            TextField("Username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal, 32)

            if let error = claimError {
                ErrorBanner(
                    error: error,
                    onDismiss: { claimError = nil },
                    isCompact: true
                )
                .padding(.horizontal, 32)
            }

            Button(action: claimUsername) {
                if isCheckingAvailability {
                    ProgressView()
                } else {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(username.isEmpty || isCheckingAvailability)
            .padding(.horizontal, 32)
        }
        .padding()
        .frame(width: 320, height: 280)
    }

    private func claimUsername() {
        guard !username.isEmpty else { return }

        isCheckingAvailability = true
        claimError = nil

        Task {
            do {
                guard let uid = AuthManager.shared.currentUser?.id else {
                    claimError = .auth(message: "Not authenticated")
                    isCheckingAvailability = false
                    return
                }

                try await UsernameService.shared.claimUsername(username, for: uid)
                onComplete()
                isCheckingAvailability = false
            } catch let err {
                claimError = AppError.from(err)
                isCheckingAvailability = false
                ErrorHandler.shared.handle(err, context: "claimUsername", showToUser: false)
            }
        }
    }
}
