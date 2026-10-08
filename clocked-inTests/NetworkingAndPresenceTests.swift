import XCTest

@testable import clocked_in

// MARK: - Date decoding

final class APIDateDecodingTests: XCTestCase {
    private struct Stamped: Decodable {
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case createdAt = "created_at"
        }
    }

    private func decode(_ json: String) throws -> Date {
        try APICoding.makeDecoder().decode(Stamped.self, from: Data(json.utf8)).createdAt
    }

    private let reference = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z

    func testDecodesWithoutFractionalSeconds() throws {
        let date = try decode(#"{"created_at": "2023-11-14T22:13:20Z"}"#)
        XCTAssertEqual(date.timeIntervalSince1970, reference.timeIntervalSince1970, accuracy: 0.001)
    }

    func testDecodesWithOffsetTimezone() throws {
        let date = try decode(#"{"created_at": "2023-11-14T22:13:20+00:00"}"#)
        XCTAssertEqual(date.timeIntervalSince1970, reference.timeIntervalSince1970, accuracy: 0.001)
    }

    func testDecodesWithMillisecondFraction() throws {
        let date = try decode(#"{"created_at": "2023-11-14T22:13:20.123Z"}"#)
        XCTAssertEqual(date.timeIntervalSince1970, reference.timeIntervalSince1970 + 0.123, accuracy: 0.001)
    }

    func testDecodesWithMicrosecondFractionAndOffset() throws {
        // Python/FastAPI emits microseconds with "+00:00"
        let date = try decode(#"{"created_at": "2023-11-14T22:13:20.123456+00:00"}"#)
        XCTAssertEqual(date.timeIntervalSince1970, reference.timeIntervalSince1970 + 0.123, accuracy: 0.001)
    }

    func testDecodesNaiveTimestampAsUTC() throws {
        let date = try decode(#"{"created_at": "2023-11-14T22:13:20.5"}"#)
        XCTAssertEqual(date.timeIntervalSince1970, reference.timeIntervalSince1970 + 0.5, accuracy: 0.001)
    }

    func testDecodesUnixMilliseconds() throws {
        let date = try decode(#"{"created_at": 1700000000000}"#)
        XCTAssertEqual(date.timeIntervalSince1970, reference.timeIntervalSince1970, accuracy: 0.001)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try decode(#"{"created_at": "yesterday"}"#))
    }
}

// MARK: - URL building

final class APIURLBuildingTests: XCTestCase {
    private let base = URL(string: "https://api.example.com")!

    func testQueryInEndpointIsNotPercentEncodedIntoPath() throws {
        let url = try XCTUnwrap(APICoding.makeURL(baseURL: base, endpoint: "/api/users/search?q=ali"))
        XCTAssertEqual(url.path, "/api/users/search")
        XCTAssertEqual(url.query, "q=ali")
        XCTAssertEqual(url.absoluteString, "https://api.example.com/api/users/search?q=ali")
    }

    func testPreEncodedQueryIsNotDoubleEncoded() throws {
        let url = try XCTUnwrap(APICoding.makeURL(baseURL: base, endpoint: "/api/users/search?q=a%20b"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items, [URLQueryItem(name: "q", value: "a b")])
    }

    func testQueryItemsParameter() throws {
        let url = try XCTUnwrap(APICoding.makeURL(
            baseURL: base,
            endpoint: "/api/users/search",
            query: [URLQueryItem(name: "q", value: "c++ & co")]
        ))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items, [URLQueryItem(name: "q", value: "c++ & co")])
        XCTAssertFalse(url.absoluteString.contains("+"), "'+' must be percent-encoded")
    }

    func testBasePathIsPreserved() throws {
        let url = try XCTUnwrap(APICoding.makeURL(
            baseURL: URL(string: "https://example.com/v1/")!,
            endpoint: "api/friends"
        ))
        XCTAssertEqual(url.absoluteString, "https://example.com/v1/api/friends")
    }

    func testNoQueryProducesNoQuestionMark() throws {
        let url = try XCTUnwrap(APICoding.makeURL(baseURL: base, endpoint: "/api/users/me"))
        XCTAssertEqual(url.absoluteString, "https://api.example.com/api/users/me")
    }
}

// MARK: - FastAPI error parsing

final class APIErrorParsingTests: XCTestCase {
    func testStringDetail() {
        let data = Data(#"{"detail": "Cannot send request"}"#.utf8)
        XCTAssertEqual(APICoding.serverMessage(from: data), "Cannot send request")
    }

    func testValidationDetailList() {
        let data = Data(#"{"detail": [{"loc": ["body", "reason"], "msg": "String should have at most 500 characters", "type": "string_too_long"}]}"#.utf8)
        XCTAssertEqual(APICoding.serverMessage(from: data), "String should have at most 500 characters")
    }

    @MainActor
    func test403IsNotAnAuthError() {
        let error = AppError.from(httpStatusCode: 403, data: Data(#"{"detail": "Cannot send request"}"#.utf8))
        XCTAssertEqual(error, .api(statusCode: 403, message: "Cannot send request"))
        XCTAssertFalse(error.requiresReauth)
    }

    @MainActor
    func test401RequiresReauth() {
        XCTAssertTrue(AppError.from(httpStatusCode: 401, data: nil).requiresReauth)
    }
}

// MARK: - FriendPresence decoding

@MainActor
final class FriendPresenceDecodingTests: XCTestCase {
    func testDecodesContractPresenceUpdate() throws {
        let json = """
        {"type": "presence_update", "user_id": "7f9c2ba4-e88f-4e35-9a3b-0d2c2f0b1a11",
         "online": true, "status": "away", "app_name": "Xcode", "bundle_id": "com.apple.dt.Xcode",
         "app_icon": "iVBORw0KGgo=", "window_title": null, "browser_domain": null,
         "updated_at": 1700000000123}
        """
        let update = try XCTUnwrap(WSDecoding.decodePayload(PresenceUpdate.self, from: Data(json.utf8)))
        XCTAssertEqual(update.userId, "7f9c2ba4-e88f-4e35-9a3b-0d2c2f0b1a11")
        XCTAssertEqual(update.online, true)
        XCTAssertEqual(update.presenceStatus, .away)
        XCTAssertEqual(update.appName, "Xcode")
        XCTAssertEqual(update.bundleId, "com.apple.dt.Xcode")
        XCTAssertEqual(update.appIconB64, "iVBORw0KGgo=")
        XCTAssertNil(update.windowTitle)
        XCTAssertNil(update.browserDomain)
        XCTAssertEqual(update.updatedAt, 1_700_000_000_123)
    }

    func testDecodesInitialPresenceFriendsList() throws {
        let json = """
        {"type": "initial_presence", "friends": [
          {"user_id": "a", "online": true, "status": "ghost", "app_name": null, "bundle_id": null,
           "app_icon": null, "window_title": null, "browser_domain": null, "updated_at": 1},
          {"user_id": "b", "online": false, "status": "offline", "app_name": null, "bundle_id": null,
           "app_icon": null, "window_title": null, "browser_domain": null, "updated_at": 2}
        ]}
        """
        let friends = try XCTUnwrap(WSDecoding.decodeInitialPresence(from: Data(json.utf8)))
        XCTAssertEqual(friends.count, 2)
        XCTAssertEqual(friends[0].presenceStatus, .ghost)
        XCTAssertNil(friends[0].appName)
        XCTAssertEqual(friends[1].online, false)
    }

    func testDecodesEmptyInitialPresence() throws {
        let json = #"{"type": "initial_presence", "friends": []}"#
        let friends = try XCTUnwrap(WSDecoding.decodeInitialPresence(from: Data(json.utf8)))
        XCTAssertTrue(friends.isEmpty)
    }

    func testDecodesLegacyNudgeWrapper() throws {
        let json = #"{"type": "nudge", "data": {"from_user_id": "u1", "from_username": "alice"}}"#
        let nudge = try XCTUnwrap(WSDecoding.decodePayload(NudgeMessage.self, from: Data(json.utf8)))
        XCTAssertEqual(nudge.fromUserId, "u1")
        XCTAssertEqual(nudge.fromUsername, "alice")
    }

    func testDisplayStatusUsesServerStatus() {
        let user = User(id: "a", username: "alice")
        XCTAssertEqual(FriendPresence(uid: "a", user: user, isOnline: true, serverStatus: .ghost).status, .ghost)
        XCTAssertEqual(FriendPresence(uid: "a", user: user, isOnline: true, serverStatus: .away).status, .away)
        XCTAssertEqual(FriendPresence(uid: "a", user: user, isOnline: false, serverStatus: .online).status, .offline)
        // Fallback to online flag
        XCTAssertEqual(FriendPresence(uid: "a", user: user, isOnline: true).status, .online)
        XCTAssertEqual(FriendPresence(uid: "a", user: user, isOnline: false).status, .offline)
    }
}

// MARK: - Presence privacy filtering

@MainActor
final class PresencePayloadTests: XCTestCase {
    // Computed (not a stored default): Activity's init is MainActor-isolated, and a
    // stored property default would run in XCTestCase's nonisolated initializers.
    private var xcode: Activity {
        Activity(
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode",
            windowTitle: "Secret.swift — MyProject",
            browserDomain: "secret.example.com",
            appIcon: Data([0x89, 0x50, 0x4E, 0x47])
        )
    }

    func testHiddenAppIsGhostWithNoAppFields() {
        let payload = PresencePayload.make(activity: xcode, isIdle: false, hiddenApps: ["com.apple.dt.Xcode"])
        XCTAssertEqual(payload, .ghost)
        XCTAssertEqual(payload.dataDictionary().keys.sorted(), ["status"])
        XCTAssertEqual(payload.dataDictionary()["status"] as? String, "ghost")
    }

    func testHiddenAppWhileIdleIsStillGhostWithNoAppFields() {
        let payload = PresencePayload.make(activity: xcode, isIdle: true, hiddenApps: ["com.apple.dt.Xcode"])
        XCTAssertEqual(payload.status, .ghost)
        XCTAssertNil(payload.appName)
        XCTAssertNil(payload.bundleId)
        XCTAssertNil(payload.appIcon)
    }

    func testVisibleAppNeverSendsWindowTitleOrDomain() {
        let payload = PresencePayload.make(activity: xcode, isIdle: false, hiddenApps: [])
        XCTAssertEqual(payload.status, .online)
        XCTAssertEqual(payload.appName, "Xcode")
        XCTAssertEqual(payload.bundleId, "com.apple.dt.Xcode")
        XCTAssertNotNil(payload.appIcon)
        let keys = Set(payload.dataDictionary().keys)
        XCTAssertEqual(keys, ["status", "app_name", "bundle_id", "app_icon"])
    }

    func testIdleVisibleAppIsAway() {
        let payload = PresencePayload.make(activity: xcode, isIdle: true, hiddenApps: [])
        XCTAssertEqual(payload.status, .away)
        XCTAssertEqual(payload.appName, "Xcode")
    }

    func testOversizedIconIsDropped() {
        var activity = xcode
        activity.appIcon = Data(repeating: 0xAB, count: 20_000) // base64 > 16 KB
        let payload = PresencePayload.make(activity: activity, isIdle: false, hiddenApps: [])
        XCTAssertNil(payload.appIcon)
        XCTAssertEqual(payload.appName, "Xcode")
    }

    func testMessageShape() {
        let message = PresencePayload.ghost.message()
        XCTAssertEqual(message["type"] as? String, "presence_update")
        XCTAssertEqual((message["data"] as? [String: Any])?["status"] as? String, "ghost")
    }
}
