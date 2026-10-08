import Foundation
import OSLog

@MainActor
@Observable
final class APIClient {
    static let shared = APIClient()

    @ObservationIgnored
    private let baseURL: URL

    @ObservationIgnored
    private var authToken: String?

    /// Silent re-authentication hook (set by AuthManager). Invoked at most once per
    /// request when the server answers 401; returns true if a fresh token was installed.
    @ObservationIgnored
    var reauthenticate: (@MainActor () async -> Bool)?

    /// True while `reauthenticate` is running. 401s seen during this window (including
    /// the re-auth request itself) are thrown without triggering another re-auth.
    @ObservationIgnored
    private(set) var isReauthenticating = false

    @ObservationIgnored
    private var reauthWaiters: [CheckedContinuation<Bool, Never>] = []

    private let log = Logger(subsystem: "com.clockedin", category: "APIClient")

    private init() {
        self.baseURL = AppConfig.shared.apiBaseURL
    }

    func setToken(_ token: String?) {
        self.authToken = token
    }

    /// The bearer token currently used for requests (read-only).
    var currentToken: String? {
        authToken
    }

    // MARK: - Core Request

    /// Performs a request and decodes the JSON response.
    /// - Parameters:
    ///   - endpoint: Path relative to the API base URL. May contain a "?query" suffix,
    ///     which is parsed and merged with `query`.
    ///   - query: Additional query items (encoded by URLComponents).
    func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let data = try await perform(endpoint, method: method, body: body, query: query, allowReauth: true)
        // 204 / empty bodies decode as an empty JSON object (e.g. EmptyResponse)
        let payload = data.isEmpty ? Data("{}".utf8) : data
        return try APICoding.makeDecoder().decode(T.self, from: payload)
    }

    /// Performs a request whose response body is ignored (e.g. 204 No Content).
    func requestNoContent(
        _ endpoint: String,
        method: String,
        body: (any Encodable)? = nil,
        query: [URLQueryItem] = []
    ) async throws {
        _ = try await perform(endpoint, method: method, body: body, query: query, allowReauth: true)
    }

    private func perform(
        _ endpoint: String,
        method: String,
        body: (any Encodable)?,
        query: [URLQueryItem],
        allowReauth: Bool
    ) async throws -> Data {
        guard let url = APICoding.makeURL(baseURL: baseURL, endpoint: endpoint, query: query) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try APICoding.makeEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            // A re-auth is already running (possibly this very request) — let it decide.
            if isReauthenticating {
                throw APIError.httpError(statusCode: 401, data: data)
            }
            if allowReauth, await attemptReauthentication() {
                log.info("Retrying \(method) \(endpoint, privacy: .public) after silent re-auth")
                return try await perform(endpoint, method: method, body: body, query: query, allowReauth: false)
            }
            ErrorHandler.shared.reportAuthFailure()
            throw APIError.httpError(statusCode: 401, data: data)
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        return data
    }

    // MARK: - Re-authentication

    /// Runs the `reauthenticate` hook once; concurrent callers share the same result.
    func attemptReauthentication() async -> Bool {
        guard let reauthenticate else { return false }

        if isReauthenticating {
            return await withCheckedContinuation { continuation in
                reauthWaiters.append(continuation)
            }
        }

        isReauthenticating = true
        let success = await reauthenticate()
        isReauthenticating = false

        let waiters = reauthWaiters
        reauthWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: success)
        }
        return success
    }

    // MARK: - Convenience methods

    func get<T: Decodable>(_ endpoint: String, query: [URLQueryItem] = []) async throws -> T {
        try await request(endpoint, method: "GET", query: query)
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

    /// DELETE that ignores the response body (204 No Content).
    func delete(_ endpoint: String) async throws {
        try await requestNoContent(endpoint, method: "DELETE")
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
        query: [URLQueryItem] = [],
        maxRetries: Int = 3,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...max(1, maxRetries) {
            do {
                return try await request(endpoint, method: method, body: body, query: query)
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

    func getWithRetry<T: Decodable>(_ endpoint: String, query: [URLQueryItem] = [], maxRetries: Int = 3) async throws -> T {
        try await requestWithRetry(endpoint, method: "GET", query: query, maxRetries: maxRetries)
    }

    func postWithRetry<T: Decodable>(_ endpoint: String, body: (any Encodable)? = nil, maxRetries: Int = 3) async throws -> T {
        try await requestWithRetry(endpoint, method: "POST", body: body, maxRetries: maxRetries)
    }
}

// MARK: - URL building & JSON coding (pure, nonisolated — unit tested)

nonisolated enum APICoding {
    /// Builds a URL from the base URL, an endpoint path (optionally containing "?query")
    /// and extra query items. Never percent-encodes the "?" into the path.
    static func makeURL(baseURL: URL, endpoint: String, query: [URLQueryItem] = []) -> URL? {
        var path = endpoint
        var items: [URLQueryItem] = []

        if let questionMark = endpoint.firstIndex(of: "?") {
            path = String(endpoint[..<questionMark])
            let rawQuery = String(endpoint[endpoint.index(after: questionMark)...])
            var parser = URLComponents()
            parser.percentEncodedQuery = rawQuery
            items.append(contentsOf: parser.queryItems ?? [])
        }
        items.append(contentsOf: query)

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var basePath = components.path
        while basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        let relativePath = path.isEmpty || path.hasPrefix("/") ? path : "/" + path
        components.path = basePath + relativePath

        if items.isEmpty {
            components.queryItems = nil
        } else {
            components.queryItems = items
            // URLComponents leaves "+" unescaped, which servers decode as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }

        return components.url
    }

    /// Parses ISO-8601 dates with or without fractional seconds (any precision),
    /// with "Z", "+00:00" or no timezone (assumed UTC).
    static func parseDate(_ rawValue: String) -> Date? {
        var string = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard string.count >= 10 else { return nil }

        // Accept "YYYY-MM-DD HH:MM:SS" (space separator)
        let separatorIndex = string.index(string.startIndex, offsetBy: 10)
        if separatorIndex < string.endIndex, string[separatorIndex] == " " {
            string.replaceSubrange(separatorIndex...separatorIndex, with: "T")
        }

        // Date only
        if !string.contains("T") {
            string += "T00:00:00Z"
        }

        var hasFraction = false
        if let dot = string.firstIndex(of: ".") {
            // Normalize fractional seconds to exactly 3 digits (ISO8601DateFormatter-friendly)
            let fractionStart = string.index(after: dot)
            var fractionEnd = fractionStart
            while fractionEnd < string.endIndex, string[fractionEnd].isASCII, string[fractionEnd].isNumber {
                fractionEnd = string.index(after: fractionEnd)
            }
            let digits = String(string[fractionStart..<fractionEnd])
            let milliseconds = String((digits + "000").prefix(3))
            string.replaceSubrange(fractionStart..<fractionEnd, with: milliseconds)
            hasFraction = true
        }

        // Append UTC designator if no timezone is present after the time
        if let timeSeparator = string.firstIndex(of: "T") {
            let timePart = string[string.index(after: timeSeparator)...]
            let hasZone = timePart.contains("Z") || timePart.contains("z")
                || timePart.contains("+") || timePart.contains("-")
            if !hasZone {
                string += "Z"
            }
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = hasFraction
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter.date(from: string)
    }

    /// JSON decoder used for all API responses. Dates may be ISO-8601 strings
    /// (with/without fractional seconds) or unix timestamps (seconds or milliseconds).
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                if let date = APICoding.parseDate(string) {
                    return date
                }
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date: \(string)"
                )
            }
            let number = try container.decode(Double.self)
            // Heuristic: values above 1e11 are milliseconds
            let seconds = number > 100_000_000_000 ? number / 1000 : number
            return Date(timeIntervalSince1970: seconds)
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Extracts a human-readable message from a FastAPI error body:
    /// `{"detail": "..."}` or `{"detail": [{"msg": "...", ...}, ...]}` (validation errors).
    /// Falls back to `message` / `error` keys.
    static func serverMessage(from data: Data?) -> String? {
        guard let data, !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return nil
        }

        if let detail = json["detail"] as? String, !detail.isEmpty {
            return detail
        }

        if let details = json["detail"] as? [[String: Any]] {
            let messages = details.compactMap { item -> String? in
                guard let msg = item["msg"] as? String, !msg.isEmpty else { return nil }
                // Pydantic prefixes custom validator messages with "Value error, "
                let prefix = "Value error, "
                return msg.hasPrefix(prefix) ? String(msg.dropFirst(prefix.count)) : msg
            }
            if !messages.isEmpty {
                return messages.joined(separator: "\n")
            }
        }

        if let detail = json["detail"] as? [String: Any],
           let msg = (detail["msg"] as? String) ?? (detail["message"] as? String),
           !msg.isEmpty {
            return msg
        }

        if let message = (json["message"] as? String) ?? (json["error"] as? String), !message.isEmpty {
            return message
        }

        return nil
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
        case .httpError(let code, let data):
            if let message = APICoding.serverMessage(from: data) {
                return message
            }
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }

    /// HTTP status code if this is an HTTP error
    var statusCode: Int? {
        if case .httpError(let code, _) = self { return code }
        return nil
    }
}
