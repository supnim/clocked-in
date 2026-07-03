import Foundation
import AuthenticationServices
import AppKit

/// Handles Apple Sign-In flow for macOS using ASAuthorizationController.
/// This service manages the native Sign in with Apple UI and coordinates
/// with the backend to complete authentication.
@MainActor
final class AppleSignInService: NSObject {
    static let shared = AppleSignInService()

    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var isSigningIn = false
    private var currentController: ASAuthorizationController?

    private override init() {
        super.init()
    }

    /// Initiates the Apple Sign-In flow and returns the credential on success.
    /// - Returns: The Apple ID credential containing identity token and user info
    /// - Throws: AppleSignInError if the flow fails or is cancelled
    func signIn() async throws -> ASAuthorizationAppleIDCredential {
        // If a previous sign-in is in flight, cancel it
        if isSigningIn, let existing = continuation {
            // Nil out the old controller's delegate to prevent stale callbacks
            currentController?.delegate = nil
            currentController = nil
            existing.resume(throwing: AppleSignInError.cancelled)
            continuation = nil
        }
        isSigningIn = true
        defer { isSigningIn = false }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.email, .fullName]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.currentController = controller
            controller.performRequests()
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                continuation?.resume(throwing: AppleSignInError.invalidCredential)
                continuation = nil
                currentController = nil
                return
            }

            continuation?.resume(returning: credential)
            continuation = nil
            currentController = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                continuation?.resume(throwing: AppleSignInError.cancelled)
            } else {
                continuation?.resume(throwing: AppleSignInError.authorizationFailed(error))
            }
            continuation = nil
            currentController = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return MainActor.assumeIsolated {
            NSApplication.shared.keyWindow
                ?? NSApplication.shared.windows.first
                ?? NSWindow()
        }
    }
}

// MARK: - Error Types

enum AppleSignInError: LocalizedError {
    case cancelled
    case invalidCredential
    case missingIdentityToken
    case authorizationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign in was cancelled"
        case .invalidCredential:
            return "Invalid Apple ID credential received"
        case .missingIdentityToken:
            return "Apple ID identity token is missing"
        case .authorizationFailed(let error):
            return "Apple Sign-In failed: \(error.localizedDescription)"
        }
    }
}
