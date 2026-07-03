import Foundation
import OSLog

@MainActor
@Observable
final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private var authToken: String?

    private init() {
        self.baseURL = AppConfig.shared.apiBaseURL
    }

    func setToken(_ token: String?) {
        self.authToken = token
    }

    func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: (any Encodable)? = nil
    ) async throws -> T {
        // Build URL
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth header
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Encode body with ISO8601 date encoding to match decoder
        if let body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(body)
        }

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            // Surface 401 through ErrorHandler for centralized auth failure handling
            if httpResponse.statusCode == 401 {
                Task {
                    ErrorHandler.shared.onAuthFailure?()
                }
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        // Decode response with ISO8601 date handling
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    // Convenience methods
    func get<T: Decodable>(_ endpoint: String) async throws -> T {
        try await request(endpoint, method: "GET")
    }

    func post<T: Decodable>(_ endpoint: String, body: (any Encodable)? = nil) async throws -> T {
        try await request(endpoint, method: "POST", body: body)
    }

    func patch<T: Decodable>(_ endpoint: String, body: (any Encodable)? = nil) async throws -> T {
        try await request(endpoint, method: "PATCH", body: body)
    }

    func delete<T: Decodable>(_ endpoint: String) async throws -> T {
        try await request(endpoint, method: "DELETE")
    }

    // MARK: - Retry Logic

    /// Makes a request with automatic retry for transient failures
    /// - Parameters:
    ///   - endpoint: API endpoint path
    ///   - method: HTTP method (GET, POST, etc.)
    ///   - body: Optional request body
    ///   - maxRetries: Maximum number of retry attempts (default: 3)
    ///   - retryableStatusCodes: HTTP status codes that should trigger a retry
    /// - Returns: Decoded response of type T
    func requestWithRetry<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        maxRetries: Int = 3,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                return try await request(endpoint, method: method, body: body)
            } catch let error as APIError {
                lastError = error

                // Check if we should retry
                let shouldRetry: Bool
                switch error {
                case .httpError(let statusCode, _):
                    shouldRetry = retryableStatusCodes.contains(statusCode)
                default:
                    shouldRetry = false
                }

                guard shouldRetry && attempt < maxRetries else {
                    throw error
                }

                // Exponential backoff: 1s, 2s, 4s, 8s...
                let backoff = pow(2.0, Double(attempt - 1))
                try await Task.sleep(for: .seconds(backoff))
            } catch let error as URLError {
                lastError = error

                // Retry on network errors
                let retryableCodes: [URLError.Code] = [
                    .timedOut,
                    .networkConnectionLost,
                    .notConnectedToInternet
                ]

                guard retryableCodes.contains(error.code) && attempt < maxRetries else {
                    throw error
                }

                // Exponential backoff: 1s, 2s, 4s, 8s...
                let backoff = pow(2.0, Double(attempt - 1))
                try await Task.sleep(for: .seconds(backoff))
            } catch {
                // Non-retryable error
                throw error
            }
        }

        throw lastError ?? APIError.invalidResponse
    }

    // MARK: - Convenience Methods with Retry

    func getWithRetry<T: Decodable>(_ endpoint: String, maxRetries: Int = 3) async throws -> T {
        try await requestWithRetry(endpoint, method: "GET", maxRetries: maxRetries)
    }

    func postWithRetry<T: Decodable>(_ endpoint: String, body: (any Encodable)? = nil, maxRetries: Int = 3) async throws -> T {
        try await requestWithRetry(endpoint, method: "POST", body: body, maxRetries: maxRetries)
    }
}

enum APIError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, _):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}
