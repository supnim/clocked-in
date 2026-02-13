import Foundation
import SwiftUI

// MARK: - App Error Types

/// Unified error type for the application
enum AppError: LocalizedError, Equatable {
    case network(message: String)
    case auth(message: String)
    case api(statusCode: Int, message: String)
    case validation(message: String)
    case notFound(resource: String)
    case rateLimited
    case serverError
    case unknown(message: String)

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return message.isEmpty ? "Network connection failed" : message
        case .auth(let message):
            return message.isEmpty ? "Authentication failed" : message
        case .api(_, let message):
            return message.isEmpty ? "Request failed" : message
        case .validation(let message):
            return message
        case .notFound(let resource):
            return "\(resource) not found"
        case .rateLimited:
            return "Too many requests"
        case .serverError:
            return "Server error"
        case .unknown(let message):
            return message.isEmpty ? "Something went wrong" : message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .network:
            return "Check your internet connection and try again"
        case .auth:
            return "Please sign in again"
        case .api(let code, _):
            if code == 401 {
                return "Your session has expired. Please sign in again."
            }
            return "Please try again"
        case .validation:
            return nil
        case .notFound:
            return "The requested item may have been removed"
        case .rateLimited:
            return "Please wait a moment before trying again"
        case .serverError:
            return "Our servers are experiencing issues. Please try again later."
        case .unknown:
            return "Please try again later"
        }
    }

    /// Whether this error should trigger a sign-out
    var requiresReauth: Bool {
        switch self {
        case .auth:
            return true
        case .api(let code, _):
            return code == 401
        default:
            return false
        }
    }

    /// Whether this is a transient error that might succeed on retry
    var isRetryable: Bool {
        switch self {
        case .network, .serverError, .rateLimited:
            return true
        case .api(let code, _):
            return code >= 500 || code == 429
        default:
            return false
        }
    }

    // MARK: - Factory Methods

    /// Creates an AppError from any Error
    static func from(_ error: Error) -> AppError {
        // Already an AppError
        if let appError = error as? AppError {
            return appError
        }

        // API errors
        if let apiError = error as? APIError {
            return from(apiError: apiError)
        }

        // Username errors
        if let usernameError = error as? UsernameError {
            return .validation(message: usernameError.localizedDescription)
        }

        // Apple Sign-In errors
        if let appleError = error as? AppleSignInError {
            return .auth(message: appleError.localizedDescription)
        }

        // URL errors (network issues)
        if let urlError = error as? URLError {
            return from(urlError: urlError)
        }

        // Decoding errors
        if error is DecodingError {
            return .api(statusCode: 0, message: "Failed to process server response")
        }

        // Generic error
        return .unknown(message: error.localizedDescription)
    }

    /// Creates an AppError from an APIError
    static func from(apiError: APIError) -> AppError {
        switch apiError {
        case .invalidResponse:
            return .api(statusCode: 0, message: "Invalid response from server")
        case .httpError(let statusCode, let data):
            return from(httpStatusCode: statusCode, data: data)
        case .decodingError:
            return .api(statusCode: 0, message: "Failed to process server response")
        }
    }

    /// Creates an AppError from an HTTP status code
    static func from(httpStatusCode: Int, data: Data?) -> AppError {
        // Try to extract error message from response body
        var message = ""
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMessage = json["message"] as? String ?? json["error"] as? String {
            message = errorMessage
        }

        switch httpStatusCode {
        case 401:
            return .auth(message: message.isEmpty ? "Session expired" : message)
        case 403:
            return .auth(message: message.isEmpty ? "Access denied" : message)
        case 404:
            return .notFound(resource: "Resource")
        case 422:
            return .validation(message: message.isEmpty ? "Invalid request" : message)
        case 429:
            return .rateLimited
        case 500...599:
            return .serverError
        default:
            return .api(statusCode: httpStatusCode, message: message)
        }
    }

    /// Creates an AppError from a URLError
    static func from(urlError: URLError) -> AppError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .network(message: "No internet connection")
        case .timedOut:
            return .network(message: "Request timed out")
        case .cannotFindHost, .cannotConnectToHost:
            return .network(message: "Cannot connect to server")
        case .userAuthenticationRequired:
            return .auth(message: "Authentication required")
        default:
            return .network(message: "Network error")
        }
    }

    // MARK: - Equatable

    static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.network(let l), .network(let r)): return l == r
        case (.auth(let l), .auth(let r)): return l == r
        case (.api(let lCode, let lMsg), .api(let rCode, let rMsg)): return lCode == rCode && lMsg == rMsg
        case (.validation(let l), .validation(let r)): return l == r
        case (.notFound(let l), .notFound(let r)): return l == r
        case (.rateLimited, .rateLimited): return true
        case (.serverError, .serverError): return true
        case (.unknown(let l), .unknown(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - Error Handler

/// Central error handler for the application
@Observable
@MainActor
final class ErrorHandler {
    static let shared = ErrorHandler()

    /// The current error being displayed (if any)
    var currentError: AppError?

    /// Whether an error is currently being shown
    var showingError = false

    /// Whether the error is a transient toast (auto-dismisses)
    var isTransient = false

    /// Callback for when auth errors require sign-out
    var onAuthFailure: (() -> Void)?

    private var autoDismissTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    /// Handle an error, converting it to AppError and displaying appropriately
    /// - Parameters:
    ///   - error: The error to handle
    ///   - context: Optional context string for logging (e.g., "fetchFriends")
    ///   - showToUser: Whether to show the error to the user (default: true)
    func handle(_ error: Error, context: String = "", showToUser: Bool = true) {
        let appError = AppError.from(error)
        logError(appError, context: context)

        // Handle auth failures specially
        if appError.requiresReauth {
            handleAuthFailure(appError)
            return
        }

        // Show to user if requested
        if showToUser {
            show(appError, isTransient: appError.isRetryable)
        }
    }

    /// Show an error to the user
    /// - Parameters:
    ///   - error: The AppError to display
    ///   - isTransient: Whether to auto-dismiss after a delay
    func show(_ error: AppError, isTransient: Bool = false) {
        autoDismissTask?.cancel()
        currentError = error
        self.isTransient = isTransient
        showingError = true

        // Auto-dismiss transient errors after 4 seconds
        if isTransient {
            autoDismissTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.dismiss()
                }
            }
        }
    }

    /// Dismiss the current error
    func dismiss() {
        autoDismissTask?.cancel()
        showingError = false
        currentError = nil
        isTransient = false
    }

    // MARK: - Private

    private func logError(_ error: AppError, context: String) {
        let contextPrefix = context.isEmpty ? "" : "[\(context)] "
        print("\(contextPrefix)Error: \(error.localizedDescription)")
        if let suggestion = error.recoverySuggestion {
            print("\(contextPrefix)Recovery: \(suggestion)")
        }
    }

    private func handleAuthFailure(_ error: AppError) {
        currentError = error
        showingError = true
        isTransient = false

        // Notify auth failure handler (typically triggers sign-out)
        onAuthFailure?()
    }
}

// MARK: - View Modifier for Error Alerts

/// View modifier that attaches error alert presentation to a view
struct ErrorAlertModifier: ViewModifier {
    @Bindable var errorHandler: ErrorHandler

    func body(content: Content) -> some View {
        content
            .alert(
                "Error",
                isPresented: $errorHandler.showingError,
                presenting: errorHandler.currentError
            ) { error in
                Button("OK") {
                    errorHandler.dismiss()
                }

                if error.isRetryable {
                    Button("Retry") {
                        errorHandler.dismiss()
                        // The retry action should be handled by the caller
                    }
                }
            } message: { error in
                VStack {
                    Text(error.localizedDescription)
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                    }
                }
            }
    }
}

extension View {
    /// Attaches the global error handler alert to this view
    func withErrorHandling() -> some View {
        modifier(ErrorAlertModifier(errorHandler: ErrorHandler.shared))
    }
}
