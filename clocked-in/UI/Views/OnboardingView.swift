import SwiftUI

struct OnboardingView: View {
    @State private var isSigningInWithGoogle = false
    @State private var isSigningInWithApple = false
    @State private var showUsernameSetup = false
    @State private var username = ""
    @State private var authError: AppError?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo/Title
            VStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)

                Text("Friends Lobby")
                    .font(.system(size: 24, weight: .bold))

                Text("See what your friends are working on in real-time")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Sign in buttons
            VStack(spacing: 12) {
                Button(action: signInWithGoogle) {
                    HStack {
                        if isSigningInWithGoogle {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "g.circle.fill")
                                .font(.system(size: 20))
                        }
                        Text("Continue with Google")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(isSigningInWithGoogle || isSigningInWithApple)

                Button(action: signInWithApple) {
                    HStack {
                        if isSigningInWithApple {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 20))
                        }
                        Text("Continue with Apple")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isSigningInWithGoogle || isSigningInWithApple)
            }
            .padding(.horizontal, 32)

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
        .frame(width: 320, height: 400)
        .sheet(isPresented: $showUsernameSetup) {
            UsernameSetupView(username: $username, onComplete: completeSetup)
        }
    }

    private func signInWithGoogle() {
        isSigningInWithGoogle = true
        authError = nil

        // Opens browser for OAuth
        AuthManager.shared.signInWithGoogle()

        // Note: The actual sign-in completion happens via deep link callback
        // The UI will update when AuthManager receives the callback
        isSigningInWithGoogle = false
    }

    private func signInWithApple() {
        isSigningInWithApple = true
        authError = nil

        Task {
            do {
                try await AuthManager.shared.signInWithApple()
                // Success - check if username setup is needed
                await MainActor.run {
                    isSigningInWithApple = false
                    if AuthManager.shared.currentUser != nil {
                        // User exists, check if they need to set up username
                        // For now, mark onboarding complete
                        completeSetup()
                    }
                }
            } catch let error as AppleSignInError {
                await MainActor.run {
                    isSigningInWithApple = false
                    // Don't show error for user cancellation
                    if case .cancelled = error {
                        authError = nil
                    } else {
                        authError = .auth(message: error.localizedDescription)
                    }
                }
            } catch let err {
                await MainActor.run {
                    isSigningInWithApple = false
                    authError = AppError.from(err)
                    ErrorHandler.shared.handle(err, context: "signInWithApple", showToUser: false)
                }
            }
        }
    }

    private func completeSetup() {
        // Mark onboarding as complete
        AppSettings.shared.hasCompletedOnboarding = true
        // Navigate to main app
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
                .font(.system(size: 18, weight: .semibold))

            Text("This will be your unique identifier for friend requests")
                .font(.system(size: 14))
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
                // Check if username is available and claim it
                guard let uid = AuthManager.shared.currentUser?.id else {
                    await MainActor.run {
                        claimError = .auth(message: "Not authenticated")
                        isCheckingAvailability = false
                    }
                    return
                }

                try await UsernameService.shared.claimUsername(username, for: uid)
                await MainActor.run {
                    onComplete()
                    isCheckingAvailability = false
                }
            } catch let err {
                await MainActor.run {
                    claimError = AppError.from(err)
                    isCheckingAvailability = false
                    ErrorHandler.shared.handle(err, context: "claimUsername", showToUser: false)
                }
            }
        }
    }
}
