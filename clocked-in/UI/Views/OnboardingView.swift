import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    /// Called once the user is authenticated and has a username.
    var onFinished: () -> Void = {}
    /// Register/sign in with the device identity as soon as the view appears.
    /// False after a user-initiated sign-out: show a "Sign In" button instead.
    var autoRegister: Bool = true

    @State private var authError: AppError?
    @State private var isRegistering = false
    @State private var needsUsername = false
    @State private var isFinishing = false
    @State private var registrationFailed = false

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

            if isRegistering || isFinishing {
                ProgressView("Setting up...")
            } else if needsUsername {
                // Show username picker after device registration (new users only)
                UsernamePickerView(onComplete: completeSetup)
            } else if registrationFailed || !autoRegister {
                Button(registrationFailed ? "Try Again" : "Sign In") {
                    Task { await registerDevice() }
                }
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
            guard autoRegister else { return }
            await registerDevice()
        }
    }

    private func registerDevice() async {
        guard !isRegistering else { return }
        isRegistering = true
        authError = nil
        registrationFailed = false
        defer { isRegistering = false }

        do {
            try await AuthManager.shared.signInWithDevice()
            if AuthManager.shared.needsUsername || !AuthManager.shared.hasUsername {
                needsUsername = true
            } else {
                // Returning user who already has a username: skip the picker
                onFinished()
            }
        } catch {
            authError = AppError.from(error)
            registrationFailed = true
        }
    }

    private func completeSetup() {
        isFinishing = true
        Task {
            // Pull the freshly claimed username into currentUser
            await AuthManager.shared.refreshCurrentUser()
            isFinishing = false
            if AuthManager.shared.isAuthenticated {
                onFinished()
            } else {
                needsUsername = false
                registrationFailed = true
                authError = .network(message: "Couldn't finish setup. Please try again.")
            }
        }
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
