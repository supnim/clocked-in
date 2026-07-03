# Clocked-In

A macOS presence app that lives in the notch/menu bar, showing friends what you're working on in real-time.

## Stack

- **Swift 6**, macOS 15+ (targeting macOS 26 Liquid Glass)
- **SwiftUI + AppKit** interop for notch/system integration
- **@Observable macro** (NOT ObservableObject) for state management
- **Custom Backend**: FastAPI, Postgres 18 (profiles/friends), Redis (presence, 45s TTL)
- **Auth**: device-UUID on first run (primary), with optional Apple Sign-In and Google OAuth (browser-redirect) for account linking
- **XcodeBuildMCP** for builds - use MCP tools, not raw xcodebuild

## Architecture

**MVVM with State Machine**

```
NotchViewModel (state machine)
├── States: closed → opened → popping
├── Open reasons: click, hover, notification, boot
└── Content: usernamePicker, lobby, settings, addFriend, pendingRequests, friendDetail

Data Flow:
ActivityMonitor → PresenceManager → WebSocketClient → PresenceListener → UI
```

**Singletons**: `AuthManager.shared`, `PresenceManager.shared`, `FriendService.shared`, `APIClient.shared`

## Directory Structure

```
clocked-in/
├── App/                    # Entry point, AppDelegate
├── Core/
│   ├── Activity/          # NSWorkspace monitoring (2s debounce)
│   ├── Events/            # Global mouse/keyboard tracking
│   ├── Friends/           # Invite link generation
│   ├── Notch/             # ViewModel, geometry, window controller
│   ├── Notifications/     # Notch-specific notification manager
│   └── Presence/          # Presence sync via WebSocket
├── Models/                # User, Activity, FriendPresence, AppSettings
├── Services/
│   ├── API/               # APIClient
│   ├── Auth/              # AuthManager, IdentityService, UsernameService, AppleSignInService
│   ├── Friends/           # FriendService
│   ├── Notifications/     # macOS notification handling
│   └── WebSocket/         # WebSocketClient
├── UI/
│   ├── Components/        # Reusable: ActionButton, FriendRow, PresenceIndicator
│   ├── NotchContent/      # CompactNotchView, ExpandedNotchView
│   └── Views/             # LobbyView, SettingsView, AddFriendView, etc.
├── Utilities/             # DeepLinkHandler, LaunchAtLogin
└── Resources/             # Assets, Info.plist
```

## Code Patterns

### @Observable (2025 Pattern)
```swift
// ✅ Use this
@Observable
final class MyViewModel {
    var state: State = .initial

    @ObservationIgnored  // Non-reactive properties
    private var debounceTask: Task<Void, Never>?
}

// In View - use @State, NOT @StateObject
@State private var viewModel = MyViewModel()

// For bindings
@Bindable var viewModel: MyViewModel

// Environment injection
@Environment(AuthManager.self) var auth
```

### Async/Await Over Callbacks
```swift
// ✅ Preferred
func fetchUser() async throws -> User {
    try await APIClient.shared.getUser(id: userId)
}

// ❌ Avoid
func fetchUser(completion: @escaping (Result<User, Error>) -> Void)
```

### Guard for Early Returns
```swift
func updatePresence() async {
    guard !appSettings.isInvisible else { return }
    guard let activity = activityMonitor.currentActivity else { return }
    // ...
}
```

### Debouncing Pattern
```swift
private var debounceTask: Task<Void, Never>?

func handleActivityChange(_ activity: Activity) {
    debounceTask?.cancel()
    debounceTask = Task {
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        await uploadActivity(activity)
    }
}
```

## Backend API Patterns

### Presence Updates
```swift
// Real-time presence goes over WebSocket, not HTTP
await WebSocketClient.shared.sendPresenceUpdate(activity, status: "online")
```

### Friend Queries
```swift
// Friends list (current user, scoped by auth token)
let friends = try await FriendService.shared.getFriends()
```

## Build Commands

This is a macOS app (not iOS), so build for `macosx`, not a simulator. Prefer
XcodeBuildMCP's macOS tools when available; otherwise raw `xcodebuild`:

```bash
xcodebuild -project clocked-in.xcodeproj -scheme clocked-in build
```

Or use slash commands: `/project:build`, `/project:test`, `/project:run`

## macOS 26 / Liquid Glass

```swift
// Auto-adopts on Xcode 26 recompile

// For customization:
.glassEffect(.regular, in: .rect)

// Button styles
Button("Action") { }.buttonStyle(.glass)
Button("Primary") { }.buttonStyle(.glassProminent)

// Split toolbars with ToolbarSpacer
ToolbarSpacer(.flexible)
```

## Key Files Reference

| Purpose | File |
|---------|------|
| State machine | `Core/Notch/NotchViewModel.swift` |
| Notch positioning | `Core/Notch/NotchGeometry.swift` |
| Activity detection | `Core/Activity/ActivityMonitor.swift` |
| Browser URLs | `Core/Activity/BrowserURLFetcher.swift` |
| Presence sync | `Core/Presence/PresenceManager.swift` |
| Friend updates | `Core/Presence/PresenceListener.swift` |
| Auth flow | `Services/Auth/AuthManager.swift` |
| Deep links | `Utilities/DeepLinkHandler.swift` |

## Testing

- Test harness: pytest (backend) + XCTest (client) — minimal, being added
- Aspirational conventions once tests exist: mock `APIClient` with protocol conformance, test state machine transitions, test debounce behavior with `Task` cancellation

## Important Notes

- **Privacy-first**: Filter hidden apps client-side before uploading to backend
- **Invisible mode**: Completely stops all presence sharing
- **Heartbeat**: Server tracks last heartbeat for presence cleanup on crash/quit
- **2s debounce**: Prevents rapid API calls on app switching
- **Deep links**: `clockedin://add/{username}` for friend invites
