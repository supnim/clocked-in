# Friends Lobby Feature - Planning Document

> **Status**: Planning Complete - Ready for Implementation
> **Last Updated**: 2025-12-23
> **Confidence Level**: 96%

---

## Vision

**Complete pivot**: Transform Clocked-In from a time tracker into a social presence app. See what your friends are working on in real-time via a Dynamic Island-style notch overlay. Think Discord activity status meets macOS notch.

> "Virtual coworking space in your notch - like sitting in a cafe with friends, seeing who's grinding on what."

---

## Goals

1. **~~Minimal time tracking~~** - ❌ REMOVED - Full pivot to social presence
2. **Friends lobby** - See a list of connected friends and their current activity
3. **Activity sharing** - Share active app name (browser URLs later)
4. **Dynamic Island UI** - Port claude-island's notch UI patterns
5. **Privacy-first** - Users control what gets shared (hide apps, go invisible)

---

## User Stories

- As a user, I want to see a green dot with a count of online friends in my notch/menu bar
- As a user, I want to expand the notch to see a scrollable list of friends and what they're doing
- As a user, I want to click on a friend to see more details about their activity
- As a user, I want to hide specific apps from being shared (e.g., Messages, private apps)
- As a user, I want to go "invisible" so friends can't see my activity
- As a user, I want to sign in with Google or Apple to identify myself

---

## Technical Research Summary

### 1. Detecting Active App Changes (macOS)

**API**: `NSWorkspace.shared.frontmostApplication`
**Notification**: `NSWorkspace.didActivateApplicationNotification`

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil,
    queue: .main
) { notification in
    if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
        let appName = app.localizedName ?? "Unknown"
        let bundleID = app.bundleIdentifier ?? ""
        // Send to server...
    }
}
```

**Sources**:
- [Apple Docs - frontmostApplication](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication)
- [Apple Docs - NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)

---

### 2. Getting Browser Tab URL

**Approach**: AppleScript via `NSAppleScript`

```swift
// Chrome
let chromeScript = """
tell application "Google Chrome"
    return URL of active tab of front window
end tell
"""

// Safari
let safariScript = """
tell application "Safari"
    return URL of front document
end tell
"""

// Execute
let script = NSAppleScript(source: chromeScript)
var error: NSDictionary?
if let result = script?.executeAndReturnError(&error) {
    let url = result.stringValue
}
```

**Browser Support**:
| Browser | URL Access | Notes |
|---------|------------|-------|
| Safari | Yes | AppleScript |
| Chrome | Yes | AppleScript |
| Arc | Likely Yes | Chrome-based, needs testing |
| Firefox | No | Removed AppleScript support in v3.6 |
| Edge | Likely Yes | Chrome-based, needs testing |

**Sources**:
- [Gist - AppleScript for browser URLs](https://gist.github.com/vitorgalvao/5392178)
- [Getting URLs from Safari](https://leancrew.com/all-this/2017/04/getting-urls-from-safari/)

---

### 3. Dynamic Island UI (Notch Overlay)

**Library**: [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)

**Features**:
- Handles notch positioning, window management, animations
- Accepts any SwiftUI View
- Falls back to `.floating` style on Macs without notch
- MIT License, SPM installation
- Requires macOS 13+

```swift
import DynamicNotchKit

let notch = DynamicNotch {
    FriendsLobbyView() // Your custom SwiftUI view
}

await notch.expand()
```

**Alternative Libraries**:
- [Atoll](https://github.com/Ebullioscopic/Atoll) - More feature-rich, based on BoringNotch
- [claude-island](https://github.com/farouqaldori/claude-island) - The original inspiration

---

### 4. Backend Options

#### Option A: Firebase (Recommended for MVP)

**Pros**:
- Battle-tested real-time sync
- Built-in presence tracking (`onDisconnect`)
- Native Swift SDK
- Google/Apple Sign-In built-in
- Free tier generous

**Cons**:
- Proprietary, vendor lock-in
- NoSQL only

**Presence Pattern**:
```swift
let presenceRef = Database.database().reference(withPath: "users/\(uid)/online")
presenceRef.setValue(true)
presenceRef.onDisconnectSetValue(false)
```

**Sources**:
- [Firebase Presence System](https://firebase.google.com/docs/firestore/solutions/presence)
- [Firebase iOS Offline Capabilities](https://firebase.google.com/docs/database/ios/offline-capabilities)

#### Option B: Supabase

**Pros**:
- Open-source, can self-host
- PostgreSQL (relational data)
- Swift SDK with Presence support
- More flexible queries

**Cons**:
- Slightly more setup
- Swift SDK less mature than Firebase

**Presence Pattern**:
```swift
let channel = await supabase.channel("lobby")
await channel.subscribe()
try await channel.track(UserStatus(user: uid, app: "Figma", onlineAt: Date()))
```

**Sources**:
- [Supabase Presence Docs](https://supabase.com/docs/guides/realtime/presence)
- [Supabase Swift Discussion](https://github.com/orgs/supabase/discussions/12968)

---

## Data Model (Draft)

```swift
struct UserPresence: Codable {
    let uid: String
    let displayName: String
    let avatarURL: String?
    let isOnline: Bool
    let isInvisible: Bool
    let lastSeen: Date
    let currentActivity: Activity?
}

struct Activity: Codable {
    let appName: String
    let appBundleID: String
    let windowTitle: String?
    let browserURL: String?        // Full URL
    let browserDomain: String?     // Extracted domain
    let browserTitle: String?      // Tab title
    let timestamp: Date
}

struct UserSettings: Codable {
    let hiddenApps: [String]       // Bundle IDs to never share
    let isInvisible: Bool          // Pause all sharing
    let shareWindowTitle: Bool     // Include window titles?
    let shareBrowserURL: Bool      // Include browser URLs?
}

struct FriendConnection: Codable {
    let fromUID: String
    let toUID: String
    let status: ConnectionStatus   // pending, accepted, blocked
    let createdAt: Date
}

enum ConnectionStatus: String, Codable {
    case pending
    case accepted
    case blocked
}
```

---

## Architecture (Draft)

```
┌─────────────────────────────────────────────────────────────────┐
│                        macOS App                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │  ActivityMonitor │    │  PresenceManager │                   │
│  │  ───────────────│    │  ─────────────── │                   │
│  │  • NSWorkspace   │───▶│  • Firebase SDK  │                   │
│  │  • AppleScript   │    │  • Auth state    │                   │
│  │  • Privacy filter│    │  • Sync activity │                   │
│  └─────────────────┘    └────────┬─────────┘                   │
│                                   │                             │
│                                   ▼                             │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    DynamicNotchKit                          ││
│  │  ┌─────────────────────────────────────────────────────┐   ││
│  │  │  Compact: [●] 3 online                              │   ││
│  │  └─────────────────────────────────────────────────────┘   ││
│  │  ┌─────────────────────────────────────────────────────┐   ││
│  │  │  Expanded:                                          │   ││
│  │  │  ┌─────────────────────────────────────────────┐   │   ││
│  │  │  │ 🟢 Alice      Figma - Dashboard.fig         │   │   ││
│  │  │  │ 🟢 Bob        VS Code - api.ts              │   │   ││
│  │  │  │ 🟡 Charlie    Away (5m ago)                 │   │   ││
│  │  │  └─────────────────────────────────────────────┘   │   ││
│  │  └─────────────────────────────────────────────────────┘   ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Firebase / Supabase                         │
├─────────────────────────────────────────────────────────────────┤
│  • Authentication (Google, Apple)                               │
│  • Realtime Database (presence, activity)                       │
│  • Firestore (user profiles, friend connections)                │
└─────────────────────────────────────────────────────────────────┘
```

---

## UI Mockups (Text-based)

### Compact State (Always Visible)
```
┌──────────────────────────────────────────────────────────────────┐
│                           [NOTCH]                                │
│                         ●3 online                                │
└──────────────────────────────────────────────────────────────────┘
```

### Expanded State (On Click/Hover)
```
┌──────────────────────────────────────────────────────────────────┐
│                           [NOTCH]                                │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Friends                                           [⚙️] [×] │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │  🟢 Alice Chen                                              │ │
│  │     Figma — Dashboard.fig                                   │ │
│  │                                                             │ │
│  │  🟢 Bob Smith                                               │ │
│  │     VS Code — src/api.ts                                    │ │
│  │                                                             │ │
│  │  🟢 You (invisible)                                         │ │
│  │     Arc — github.com/user/repo                              │ │
│  │                                                             │ │
│  │  🔘 Charlie Brown                                           │ │
│  │     Last seen 5 minutes ago                                 │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

---

## Decisions Made ✅

| Question | Decision |
|----------|----------|
| **Friend discovery** | Share link + Username search |
| **Friend requests** | Mutual (both must accept) |
| **Offline state** | Show "Last seen X minutes ago" |
| **Menu bar vs Notch** | Notch only (remove menu bar, full pivot) |
| **Notifications** | Friend online + Same app alerts (grouped) |
| **App name** | Keep "Clocked-In" (new purpose) |
| **UI Framework** | **Port claude-island patterns** (NotchViewModel, geometry) + study DynamicNotchKit for edge cases |
| **Backend** | Firebase (Realtime DB + Firestore + Auth) |
| **MVP scope** | Auth, Activity tracking, Friend system, Notch UI, Notifications |
| **Activity detail** | App name + window title + app icon |
| **Rate limiting** | Debounce 2 seconds after app change |
| **Codebase approach** | Gut existing project, rebuild fresh (keep bundle ID) |

---

## Open Questions (Minor - Can Decide During Build)

1. **Share link format**: Deep link vs web URL?
   - `clockedin://add/username` (deep link)
   - `clockedin.app/add/username` (web → deep link)
   - Likely both: web link that redirects to deep link

2. **Onboarding empty state**: What shows first?
   - Sign in → Empty lobby with big "Invite Friends" CTA
   - Can refine during implementation

3. **Non-notch Mac behavior**:
   - Floating window from top-center (study DynamicNotchKit)
   - Decide during notch implementation

---

## Technical Architecture (MVP)

### Project Structure

```
clocked-in/
├── App/
│   ├── ClockedInApp.swift           # @main entry, app lifecycle
│   └── AppDelegate.swift            # NSApplication delegate, notch setup
│
├── Core/
│   ├── Notch/
│   │   ├── NotchViewModel.swift     # State machine (ported from claude-island)
│   │   ├── NotchGeometry.swift      # Positioning calculations
│   │   ├── NotchWindowController.swift
│   │   └── NotchContentType.swift   # Enum: lobby, settings, friendDetail
│   │
│   ├── Activity/
│   │   ├── ActivityMonitor.swift    # NSWorkspace observer
│   │   ├── ActivityDebouncer.swift  # 2-second debounce logic
│   │   └── BrowserURLFetcher.swift  # AppleScript (v1.1+)
│   │
│   ├── Presence/
│   │   ├── PresenceManager.swift    # Firebase sync orchestrator
│   │   ├── PresenceListener.swift   # Listen to friends' presence
│   │   └── OnlineStatusTracker.swift
│   │
│   └── Friends/
│       ├── FriendManager.swift      # Add/remove/search friends
│       ├── FriendRequestHandler.swift
│       └── InviteLinkGenerator.swift
│
├── Models/
│   ├── User.swift                   # User profile
│   ├── Activity.swift               # Current app/window
│   ├── FriendPresence.swift         # Friend's online status + activity
│   ├── FriendRequest.swift          # Pending request
│   └── AppSettings.swift            # Local preferences
│
├── Services/
│   ├── Firebase/
│   │   ├── AuthService.swift        # Google/Apple sign-in
│   │   ├── RealtimeDBService.swift  # Presence data
│   │   ├── FirestoreService.swift   # Profiles, friends
│   │   └── FirebaseConfig.swift
│   │
│   └── Notifications/
│       ├── NotificationManager.swift
│       └── NotificationGrouper.swift # Group "same app" alerts
│
├── UI/
│   ├── Components/
│   │   ├── PresenceIndicator.swift  # 🟢🟡⚫ status dot
│   │   ├── FriendRow.swift          # Avatar + name + activity
│   │   ├── AppIconView.swift        # Display app icon
│   │   ├── ActionButton.swift
│   │   └── NotchShape.swift         # Custom notch outline
│   │
│   ├── Views/
│   │   ├── LobbyView.swift          # Main friends list
│   │   ├── FriendDetailView.swift   # Expanded friend info
│   │   ├── SettingsView.swift       # Sign out, profile
│   │   ├── AddFriendView.swift      # Search + invite link
│   │   ├── PendingRequestsView.swift
│   │   ├── OnboardingView.swift     # Sign in flow
│   │   └── EmptyStateView.swift     # No friends yet
│   │
│   └── NotchContent/
│       ├── CompactNotchView.swift   # Green dot + count
│       └── ExpandedNotchView.swift  # Full lobby
│
├── Utilities/
│   ├── Ext+NSScreen.swift
│   ├── Ext+NSRunningApplication.swift
│   ├── DeepLinkHandler.swift
│   └── Constants.swift
│
└── Resources/
    ├── Assets.xcassets/
    ├── GoogleService-Info.plist
    └── Info.plist
```

---

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              LOCAL (macOS)                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌──────────────────┐     ┌──────────────────┐                        │
│   │  ActivityMonitor │     │  NotchViewModel  │                        │
│   │  ──────────────  │     │  ──────────────  │                        │
│   │  NSWorkspace     │     │  status: closed/ │                        │
│   │  .didActivate    │     │    opened/popping│                        │
│   │  Notification    │     │  contentType     │                        │
│   └────────┬─────────┘     │  isHovering      │                        │
│            │               └────────┬─────────┘                        │
│            │ (app changed)          │                                   │
│            ▼                        ▼                                   │
│   ┌──────────────────┐     ┌──────────────────┐                        │
│   │ ActivityDebouncer│     │   NotchWindow    │                        │
│   │  ──────────────  │     │  ──────────────  │                        │
│   │  2 sec debounce  │     │  CompactView     │◄──── Hover/Click ────┐ │
│   └────────┬─────────┘     │  ExpandedView    │                      │ │
│            │               └──────────────────┘                      │ │
│            │                        ▲                                │ │
│            ▼                        │                                │ │
│   ┌──────────────────┐     ┌───────┴──────────┐                      │ │
│   │ PresenceManager  │     │ PresenceListener │                      │ │
│   │  ──────────────  │     │  ──────────────  │    ┌────────────┐    │ │
│   │  Upload my       │     │  Subscribe to    │───▶│ LobbyView  │────┘ │
│   │  activity        │     │  friends' data   │    │ FriendRows │      │
│   └────────┬─────────┘     └────────┬─────────┘    └────────────┘      │
│            │                        │                                   │
└────────────┼────────────────────────┼───────────────────────────────────┘
             │                        │
             ▼                        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              FIREBASE                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │                     Realtime Database                            │  │
│   │  ─────────────────────────────────────────────────────────────  │  │
│   │  /presence/{uid}                                                 │  │
│   │    ├── online: true                                              │  │
│   │    ├── lastSeen: 1703345678                                      │  │
│   │    ├── appName: "Figma"                                          │  │
│   │    ├── appBundleId: "com.figma.Desktop"                          │  │
│   │    ├── windowTitle: "Dashboard.fig"                              │  │
│   │    ├── appIconBase64: "iVBORw0KGgo..."  (optional, cached)       │  │
│   │    └── updatedAt: 1703345678                                     │  │
│   │                                                                   │  │
│   │  onDisconnect() → sets online: false, lastSeen: serverTimestamp │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │                        Firestore                                 │  │
│   │  ─────────────────────────────────────────────────────────────  │  │
│   │  /users/{uid}                                                    │  │
│   │    ├── displayName: "Nimesh"                                     │  │
│   │    ├── username: "nimesh" (unique, searchable)                   │  │
│   │    ├── avatarURL: "https://..."                                  │  │
│   │    ├── email: "..."                                              │  │
│   │    └── createdAt: Timestamp                                      │  │
│   │                                                                   │  │
│   │  /friends/{oderedUidPair}                                        │  │
│   │    ├── users: [uid1, uid2]                                       │  │
│   │    ├── status: "accepted" | "pending"                            │  │
│   │    ├── initiatedBy: uid1                                         │  │
│   │    └── createdAt: Timestamp                                      │  │
│   │                                                                   │  │
│   │  /friendRequests/{recipientUid}/incoming/{senderUid}             │  │
│   │    ├── from: uid                                                 │  │
│   │    ├── fromName: "Alice"                                         │  │
│   │    └── createdAt: Timestamp                                      │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### Key Implementations

#### 1. Activity Monitor (NSWorkspace)

```swift
class ActivityMonitor: ObservableObject {
    @Published var currentActivity: Activity?
    private var debounceTask: Task<Void, Never>?

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppChange(notification)
        }
    }

    private func handleAppChange(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication else { return }

        // Cancel previous debounce
        debounceTask?.cancel()

        // Debounce 2 seconds
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.currentActivity = Activity(
                    appName: app.localizedName ?? "Unknown",
                    bundleId: app.bundleIdentifier ?? "",
                    windowTitle: self.getWindowTitle(for: app),
                    appIcon: app.icon,
                    timestamp: Date()
                )
            }
        }
    }

    private func getWindowTitle(for app: NSRunningApplication) -> String? {
        // Use Accessibility API or CGWindowList
        // Implementation details...
    }
}
```

#### 2. Presence Manager (Firebase Sync)

```swift
class PresenceManager {
    private let db = Database.database()
    private let uid: String

    func startPresence() {
        let presenceRef = db.reference(withPath: "presence/\(uid)")
        let connectedRef = db.reference(withPath: ".info/connected")

        connectedRef.observe(.value) { [weak self] snapshot in
            guard let connected = snapshot.value as? Bool, connected else { return }

            // When we disconnect, update lastSeen and set online = false
            presenceRef.onDisconnectSetValue([
                "online": false,
                "lastSeen": ServerValue.timestamp()
            ])

            // Set online = true now
            presenceRef.setValue([
                "online": true,
                "lastSeen": ServerValue.timestamp()
            ])
        }
    }

    func updateActivity(_ activity: Activity) {
        let presenceRef = db.reference(withPath: "presence/\(uid)")
        presenceRef.updateChildValues([
            "appName": activity.appName,
            "appBundleId": activity.bundleId,
            "windowTitle": activity.windowTitle ?? "",
            "updatedAt": ServerValue.timestamp()
        ])
    }
}
```

#### 3. NotchViewModel (State Machine)

```swift
enum NotchStatus {
    case closed, opened, popping
}

enum NotchOpenReason {
    case click, hover, notification, boot
}

enum NotchContentType {
    case lobby, settings, friendDetail(FriendPresence), addFriend
}

@Observable
class NotchViewModel {
    var status: NotchStatus = .closed
    var openReason: NotchOpenReason = .boot
    var contentType: NotchContentType = .lobby
    var isHovering = false

    private var hoverTimer: DispatchWorkItem?
    private let hoverDelay: TimeInterval = 1.0

    let geometry: NotchGeometry

    // MARK: - Hover Handling

    func handleMouseEnter() {
        isHovering = true

        hoverTimer?.cancel()
        hoverTimer = DispatchWorkItem { [weak self] in
            self?.notchOpen(reason: .hover)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: hoverTimer!)
    }

    func handleMouseExit() {
        isHovering = false
        hoverTimer?.cancel()

        if status == .opened && openReason == .hover {
            notchClose()
        }
    }

    // MARK: - State Transitions

    func notchOpen(reason: NotchOpenReason) {
        openReason = reason
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            status = .opened
        }
    }

    func notchClose() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            status = .closed
        }
    }

    func notchPop() {
        // Brief expand animation on boot
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            status = .popping
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.notchClose()
        }
    }
}
```

#### 4. Notification Grouper

```swift
class NotificationGrouper {
    private var pendingSameAppNotifications: [String: [FriendPresence]] = [:]
    private var debounceTask: Task<Void, Never>?

    func friendChangedApp(_ friend: FriendPresence, myCurrentApp: String) {
        guard friend.appName == myCurrentApp else { return }

        // Group by app name
        pendingSameAppNotifications[friend.appName, default: []].append(friend)

        // Debounce to group multiple friends
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.sendGroupedNotification()
            }
        }
    }

    private func sendGroupedNotification() {
        for (appName, friends) in pendingSameAppNotifications {
            let names = friends.map { $0.displayName }
            let message = formatNames(names) + " in \(appName)"
            // "Alice, Bob, and Charlie are in Figma"
            NotificationManager.shared.send(title: "Same App", body: message)
        }
        pendingSameAppNotifications.removeAll()
    }
}
```

#### 5. Window Title Extraction (CGWindowList)

```swift
extension ActivityMonitor {
    func getWindowTitle(for app: NSRunningApplication) -> String? {
        // Get all windows
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        // Find window belonging to this app
        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == app.processIdentifier,
                  let windowName = window[kCGWindowName as String] as? String,
                  !windowName.isEmpty else { continue }
            return windowName
        }
        return nil
    }
}
```

#### 6. Notch Window Controller

```swift
class NotchWindowController: NSWindowController {
    private var trackingArea: NSTrackingArea?

    convenience init(content: some View, geometry: NotchGeometry) {
        let window = NSWindow(
            contentRect: geometry.notchScreenRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Window configuration
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu  // Above menu bar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = false

        // Set SwiftUI content
        window.contentView = NSHostingView(rootView: content)

        self.init(window: window)
        setupMouseTracking()
    }

    private func setupMouseTracking() {
        guard let contentView = window?.contentView else { return }

        trackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeAlways,
                .inVisibleRect  // Auto-updates with view bounds
            ],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        NotificationCenter.default.post(name: .notchMouseEntered, object: nil)
    }

    override func mouseExited(with event: NSEvent) {
        NotificationCenter.default.post(name: .notchMouseExited, object: nil)
    }
}

extension Notification.Name {
    static let notchMouseEntered = Notification.Name("notchMouseEntered")
    static let notchMouseExited = Notification.Name("notchMouseExited")
}
```

#### 7. Non-Notch Mac Detection

```swift
extension NSScreen {
    var hasNotch: Bool {
        guard let auxiliaryTopLeftArea = auxiliaryTopLeftArea,
              let auxiliaryTopRightArea = auxiliaryTopRightArea else {
            return false
        }
        // If there's a gap between left and right areas, there's a notch
        return auxiliaryTopRightArea.minX > auxiliaryTopLeftArea.maxX
    }

    var notchSize: CGSize? {
        guard hasNotch,
              let leftArea = auxiliaryTopLeftArea,
              let rightArea = auxiliaryTopRightArea else { return nil }

        let width = rightArea.minX - leftArea.maxX
        let height = max(leftArea.height, rightArea.height)
        return CGSize(width: width, height: height)
    }
}

// Fallback for non-notch Macs: floating window at top-center
struct NotchGeometry {
    static func create(for screen: NSScreen) -> NotchGeometry {
        if screen.hasNotch, let notchSize = screen.notchSize {
            // Notch Mac: position at notch
            return NotchGeometry(
                deviceNotchRect: CGRect(origin: .zero, size: notchSize),
                screenRect: screen.frame,
                style: .notch
            )
        } else {
            // Non-notch Mac: floating at top center
            let defaultSize = CGSize(width: 200, height: 32)
            return NotchGeometry(
                deviceNotchRect: CGRect(origin: .zero, size: defaultSize),
                screenRect: screen.frame,
                style: .floating
            )
        }
    }

    enum Style { case notch, floating }
    let deviceNotchRect: CGRect
    let screenRect: CGRect
    let style: Style
}
```

#### 8. Deep Link Handler

```swift
// Info.plist configuration:
// CFBundleURLTypes > Item 0 > CFBundleURLSchemes > clockedin

class DeepLinkHandler {
    static let shared = DeepLinkHandler()

    func handle(url: URL) {
        guard url.scheme == "clockedin" else { return }

        switch url.host {
        case "add":
            // clockedin://add/username
            if let username = url.pathComponents.dropFirst().first {
                handleAddFriend(username: username)
            }
        case "invite":
            // clockedin://invite/CODE123
            if let code = url.pathComponents.dropFirst().first {
                handleInviteCode(code: code)
            }
        default:
            break
        }
    }

    private func handleAddFriend(username: String) {
        // Show add friend confirmation
        NotificationCenter.default.post(
            name: .showAddFriendConfirmation,
            object: username
        )
    }
}

// In SwiftUI App:
@main
struct ClockedInApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }  // Hide settings window
            .handlesExternalEvents(matching: [])
    }
}

// In AppDelegate:
func application(_ application: NSApplication, open urls: [URL]) {
    urls.forEach { DeepLinkHandler.shared.handle(url: $0) }
}
```

#### 9. Unique Username with Transaction

```swift
class UsernameService {
    private let db = Firestore.firestore()

    func claimUsername(_ username: String, for uid: String) async throws -> Bool {
        let usernameRef = db.collection("usernames").document(username.lowercased())
        let userRef = db.collection("users").document(uid)

        return try await db.runTransaction { transaction, errorPointer in
            // Check if username already taken
            let usernameDoc: DocumentSnapshot
            do {
                usernameDoc = try transaction.getDocument(usernameRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return false
            }

            if usernameDoc.exists {
                // Username taken
                return false
            }

            // Claim username atomically
            transaction.setData(["uid": uid, "createdAt": FieldValue.serverTimestamp()], forDocument: usernameRef)
            transaction.updateData(["username": username.lowercased()], forDocument: userRef)

            return true
        }
    }

    func searchUsers(query: String) async throws -> [User] {
        let snapshot = try await db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: query.lowercased())
            .whereField("username", isLessThan: query.lowercased() + "\u{f8ff}")
            .limit(to: 10)
            .getDocuments()

        return snapshot.documents.compactMap { try? $0.data(as: User.self) }
    }
}
```

---

### Firebase Security Rules

```javascript
// Realtime Database Rules
{
  "rules": {
    "presence": {
      "$uid": {
        ".read": "auth != null",  // Any authenticated user can read
        ".write": "auth.uid === $uid"  // Only owner can write
      }
    }
  }
}

// Firestore Rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }

    match /friends/{friendshipId} {
      allow read: if request.auth.uid in resource.data.users;
      allow create: if request.auth.uid in request.resource.data.users;
      allow update: if request.auth.uid in resource.data.users;
      allow delete: if request.auth.uid in resource.data.users;
    }

    match /friendRequests/{recipientUid}/incoming/{senderId} {
      allow read: if request.auth.uid == recipientUid;
      allow create: if request.auth.uid == senderId;
      allow delete: if request.auth.uid == recipientUid
                    || request.auth.uid == senderId;
    }
  }
}
```

---

## Step-by-Step Implementation Checklist

> Each task is granular enough to complete in one sitting. Check off as you go.

---

### Phase 1: Project Setup (Day 1)

#### 1.1 Clean Existing Codebase
- [ ] Create a new git branch: `feature/friends-lobby`
- [ ] Delete: `PercentageCalculator.swift`
- [ ] Delete: `MenuBarViewModel.swift`
- [ ] Delete: `StatusBarRenderer.swift`
- [ ] Delete: `OnboardingView.swift` (will rebuild)
- [ ] Delete: `SettingsView.swift` (will rebuild)
- [ ] Keep: `AppDelegate.swift` (will modify)
- [ ] Keep: `Settings.swift` → rename to `AppSettings.swift`
- [ ] Keep: `LaunchAtLogin.swift`
- [ ] Keep: `Assets.xcassets`

#### 1.2 Create New Folder Structure
- [ ] Create folder: `clocked-in/App/`
- [ ] Create folder: `clocked-in/Core/Notch/`
- [ ] Create folder: `clocked-in/Core/Activity/`
- [ ] Create folder: `clocked-in/Core/Presence/`
- [ ] Create folder: `clocked-in/Core/Friends/`
- [ ] Create folder: `clocked-in/Models/`
- [ ] Create folder: `clocked-in/Services/Firebase/`
- [ ] Create folder: `clocked-in/Services/Notifications/`
- [ ] Create folder: `clocked-in/UI/Components/`
- [ ] Create folder: `clocked-in/UI/Views/`
- [ ] Create folder: `clocked-in/UI/NotchContent/`
- [ ] Create folder: `clocked-in/Utilities/`

#### 1.3 Firebase Project Setup
- [ ] Go to [Firebase Console](https://console.firebase.google.com)
- [ ] Create new project: "Clocked-In"
- [ ] Add macOS app with bundle ID
- [ ] Download `GoogleService-Info.plist` → add to project
- [ ] Enable Authentication > Sign-in methods > Google
- [ ] Enable Authentication > Sign-in methods > Apple
- [ ] Create Realtime Database (Start in test mode)
- [ ] Create Firestore Database (Start in test mode)

#### 1.4 Add Firebase SDK via SPM
- [ ] Xcode > File > Add Package Dependencies
- [ ] URL: `https://github.com/firebase/firebase-ios-sdk`
- [ ] Select: `FirebaseAuth`, `FirebaseFirestore`, `FirebaseDatabase`
- [ ] Add `-ObjC` to Other Linker Flags
- [ ] Enable Keychain Sharing capability
- [ ] Add Google Sign-In SDK: `https://github.com/google/GoogleSignIn-iOS`

#### 1.5 Configure Info.plist
- [ ] Add URL Scheme for Google Sign-In (REVERSED_CLIENT_ID from plist)
- [ ] Add URL Scheme: `clockedin` (for deep links)
- [ ] Add Sign In with Apple capability
- [ ] Add `NSApplicationSupportsSecureRestorableState = YES`

---

### Phase 2: Core Models (Day 2)

#### 2.1 Create Data Models
- [ ] Create `Models/User.swift`:
  ```swift
  struct User: Codable, Identifiable {
      @DocumentID var id: String?
      var displayName: String
      var username: String
      var email: String
      var avatarURL: String?
      var createdAt: Date
  }
  ```

- [ ] Create `Models/Activity.swift`:
  ```swift
  struct Activity: Codable {
      var appName: String
      var bundleId: String
      var windowTitle: String?
      var appIcon: Data?  // PNG data
      var timestamp: Date
  }
  ```

- [ ] Create `Models/FriendPresence.swift`:
  ```swift
  struct FriendPresence: Identifiable {
      var id: String { uid }
      var uid: String
      var user: User
      var isOnline: Bool
      var lastSeen: Date
      var currentActivity: Activity?

      var status: PresenceStatus {
          if !isOnline { return .offline }
          guard let activity = currentActivity else { return .online }
          let minutesAgo = Date().timeIntervalSince(activity.timestamp) / 60
          return minutesAgo < 5 ? .active : .idle
      }
  }

  enum PresenceStatus {
      case active   // 🟢 App changed in last 5 min
      case idle     // 🟡 No change in 5+ min
      case offline  // ⚫ Not online
  }
  ```

- [ ] Create `Models/FriendRequest.swift`:
  ```swift
  struct FriendRequest: Codable, Identifiable {
      @DocumentID var id: String?
      var fromUid: String
      var fromName: String
      var fromAvatar: String?
      var createdAt: Date
  }
  ```

- [ ] Create `Models/AppSettings.swift`:
  ```swift
  @Observable
  class AppSettings {
      static let shared = AppSettings()

      @AppStorage("hiddenApps") var hiddenApps: [String] = []
      @AppStorage("isInvisible") var isInvisible: Bool = false
      @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
  }
  ```

---

### Phase 3: Firebase Services (Day 2-3)

#### 3.1 Auth Service
- [ ] Create `Services/Firebase/AuthService.swift`
- [ ] Implement `signInWithGoogle()` using GIDSignIn
- [ ] Implement `signInWithApple()` using ASAuthorizationController
- [ ] Implement `signOut()`
- [ ] Implement `currentUser` computed property
- [ ] Add auth state listener

#### 3.2 Firestore Service
- [ ] Create `Services/Firebase/FirestoreService.swift`
- [ ] Implement `createUserProfile(user:)`
- [ ] Implement `getUser(uid:)` async
- [ ] Implement `updateUser(uid:, data:)`
- [ ] Implement `searchUsers(query:)` for username search
- [ ] Implement `claimUsername(username:, uid:)` with transaction

#### 3.3 Realtime DB Service
- [ ] Create `Services/Firebase/RealtimeDBService.swift`
- [ ] Implement `setOnline(uid:)`
- [ ] Implement `setOffline(uid:)`
- [ ] Implement `updateActivity(uid:, activity:)`
- [ ] Implement `observePresence(uid:, callback:)`
- [ ] Implement `setupOnDisconnect(uid:)`

#### 3.4 Friend Service
- [ ] Create `Services/Firebase/FriendService.swift`
- [ ] Implement `sendFriendRequest(toUid:)`
- [ ] Implement `acceptFriendRequest(fromUid:)`
- [ ] Implement `declineFriendRequest(fromUid:)`
- [ ] Implement `getFriends()` → returns [String] of friend UIDs
- [ ] Implement `observeFriendRequests(callback:)`
- [ ] Implement `removeFriend(uid:)`

---

### Phase 4: Activity Monitoring (Day 3-4)

#### 4.1 Activity Monitor
- [ ] Create `Core/Activity/ActivityMonitor.swift`
- [ ] Add NSWorkspace notification observer
- [ ] Implement 2-second debounce with Task
- [ ] Extract app name from NSRunningApplication
- [ ] Extract bundle ID from NSRunningApplication
- [ ] Extract app icon from NSRunningApplication

#### 4.2 Window Title Extraction
- [ ] Implement `getWindowTitle(for app:)` using CGWindowListCopyWindowInfo
- [ ] Filter windows by process ID
- [ ] Return first non-empty window name

#### 4.3 Presence Manager
- [ ] Create `Core/Presence/PresenceManager.swift`
- [ ] Subscribe to ActivityMonitor changes
- [ ] Filter out hidden apps from AppSettings
- [ ] Upload activity to Firebase on change
- [ ] Handle invisible mode

#### 4.4 Presence Listener
- [ ] Create `Core/Presence/PresenceListener.swift`
- [ ] Get list of friend UIDs from FriendService
- [ ] Observe each friend's `/presence/{uid}` node
- [ ] Combine with user profile data
- [ ] Publish `[FriendPresence]` array
- [ ] Detect friend coming online (was offline, now online)
- [ ] Detect friend using same app

---

### Phase 5: Notch UI (Day 4-5)

#### 5.1 Notch Geometry
- [ ] Create `Core/Notch/NotchGeometry.swift`
- [ ] Implement `NSScreen.hasNotch` extension
- [ ] Implement `NSScreen.notchSize` extension
- [ ] Implement `NotchGeometry.create(for screen:)`
- [ ] Handle non-notch Mac fallback (floating style)
- [ ] Implement `notchScreenRect` computed property
- [ ] Implement `openedScreenRect(for size:)`

#### 5.2 Notch View Model
- [ ] Create `Core/Notch/NotchViewModel.swift`
- [ ] Define `NotchStatus` enum: closed, opened, popping
- [ ] Define `NotchOpenReason` enum: click, hover, notification, boot
- [ ] Define `NotchContentType` enum: lobby, settings, addFriend, friendDetail
- [ ] Implement hover handling with 1-second delay
- [ ] Implement `notchOpen(reason:)`
- [ ] Implement `notchClose()`
- [ ] Implement `notchPop()` for boot animation

#### 5.3 Notch Window Controller
- [ ] Create `Core/Notch/NotchWindowController.swift`
- [ ] Create NSWindow with borderless style
- [ ] Set window level to `.popUpMenu`
- [ ] Set collectionBehavior for all spaces
- [ ] Set up NSTrackingArea for mouse events
- [ ] Post notifications for mouse enter/exit

#### 5.4 Compact Notch View
- [ ] Create `UI/NotchContent/CompactNotchView.swift`
- [ ] Show green dot indicator
- [ ] Show online friends count
- [ ] Match notch shape with rounded corners
- [ ] Handle click to expand

#### 5.5 Expanded Notch View
- [ ] Create `UI/NotchContent/ExpandedNotchView.swift`
- [ ] Show header with "Friends" title
- [ ] Add settings gear button
- [ ] Add close X button
- [ ] Show ScrollView of FriendRow items
- [ ] Handle empty state

---

### Phase 6: UI Components (Day 5-6)

#### 6.1 Presence Indicator
- [ ] Create `UI/Components/PresenceIndicator.swift`
- [ ] 🟢 Green circle for active
- [ ] 🟡 Yellow circle for idle
- [ ] ⚫ Gray circle for offline
- [ ] Add subtle animation/pulse for active

#### 6.2 Friend Row
- [ ] Create `UI/Components/FriendRow.swift`
- [ ] Show avatar (AsyncImage from URL)
- [ ] Show display name
- [ ] Show PresenceIndicator
- [ ] Show activity (app name + window title)
- [ ] Show app icon if available
- [ ] Show "Last seen X ago" for offline friends
- [ ] Handle tap to show detail

#### 6.3 App Icon View
- [ ] Create `UI/Components/AppIconView.swift`
- [ ] Display app icon from Data
- [ ] Fallback to generic app icon
- [ ] Size: 16x16 or 20x20

#### 6.4 Action Button
- [ ] Create `UI/Components/ActionButton.swift`
- [ ] Minimal style for settings/close buttons
- [ ] Hover state

---

### Phase 7: Views (Day 6-7)

#### 7.1 Lobby View
- [ ] Create `UI/Views/LobbyView.swift`
- [ ] List of FriendRow items
- [ ] Section for online friends
- [ ] Section for offline friends
- [ ] Pull to refresh (if applicable)

#### 7.2 Add Friend View
- [ ] Create `UI/Views/AddFriendView.swift`
- [ ] Username search TextField
- [ ] Search results list
- [ ] Send request button
- [ ] "Share your link" section
- [ ] Copy link button

#### 7.3 Pending Requests View
- [ ] Create `UI/Views/PendingRequestsView.swift`
- [ ] List of incoming requests
- [ ] Accept/Decline buttons per request
- [ ] Badge count on notch when requests pending

#### 7.4 Settings View
- [ ] Create `UI/Views/SettingsView.swift`
- [ ] Show current user profile
- [ ] Sign out button
- [ ] Launch at login toggle
- [ ] (Later: hidden apps, invisible mode)

#### 7.5 Onboarding View
- [ ] Create `UI/Views/OnboardingView.swift`
- [ ] Welcome message
- [ ] Sign in with Google button
- [ ] Sign in with Apple button
- [ ] Username selection step (after auth)

#### 7.6 Empty State View
- [ ] Create `UI/Views/EmptyStateView.swift`
- [ ] "No friends yet" message
- [ ] Big "Invite Friends" CTA
- [ ] Illustration (optional)

---

### Phase 8: Notifications (Day 7)

#### 8.1 Notification Manager
- [ ] Create `Services/Notifications/NotificationManager.swift`
- [ ] Request notification permission
- [ ] Implement `send(title:, body:)`
- [ ] Handle notification tap (open app, show lobby)

#### 8.2 Notification Grouper
- [ ] Create `Services/Notifications/NotificationGrouper.swift`
- [ ] Group "same app" notifications
- [ ] 1-second debounce before sending
- [ ] Format: "Alice, Bob, and Charlie are in Figma"

#### 8.3 Notification Triggers
- [ ] Trigger on friend comes online
- [ ] Trigger on friend using same app as you
- [ ] Respect user preferences (later: mute specific friends)

---

### Phase 9: Deep Links (Day 7-8)

#### 9.1 Deep Link Handler
- [ ] Create `Utilities/DeepLinkHandler.swift`
- [ ] Handle `clockedin://add/{username}`
- [ ] Handle `clockedin://invite/{code}` (future)
- [ ] Show confirmation before sending request

#### 9.2 Invite Link Generator
- [ ] Create `Core/Friends/InviteLinkGenerator.swift`
- [ ] Generate link: `clockedin://add/{username}`
- [ ] Copy to clipboard function
- [ ] (Future: web link that redirects to deep link)

---

### Phase 10: App Integration (Day 8)

#### 10.1 App Delegate
- [ ] Modify `AppDelegate.swift`
- [ ] Initialize Firebase on launch
- [ ] Create NotchWindowController
- [ ] Set up NotchViewModel
- [ ] Start ActivityMonitor when signed in
- [ ] Start PresenceManager when signed in
- [ ] Handle deep link URLs

#### 10.2 App Entry Point
- [ ] Modify/Create `ClockedInApp.swift`
- [ ] Use NSApplicationDelegateAdaptor
- [ ] Handle app lifecycle
- [ ] No main window (notch only)

#### 10.3 Auth State Handling
- [ ] Show onboarding if not signed in
- [ ] Show notch if signed in
- [ ] Handle sign out (stop services, show onboarding)

---

### Phase 11: Testing & Polish (Day 8-9)

#### 11.1 Manual Testing
- [ ] Test Google Sign-In flow
- [ ] Test Apple Sign-In flow
- [ ] Test username claim (unique)
- [ ] Test username search
- [ ] Test send friend request
- [ ] Test accept friend request
- [ ] Test activity tracking (switch apps)
- [ ] Test presence updates in real-time
- [ ] Test notifications (friend online, same app)
- [ ] Test deep link: `clockedin://add/testuser`
- [ ] Test on non-notch Mac (floating fallback)

#### 11.2 Edge Cases
- [ ] Rapid app switching (debounce works)
- [ ] Network disconnection (offline handling)
- [ ] Multiple friends come online at once
- [ ] Empty friends list UI
- [ ] Very long app names / window titles
- [ ] Missing avatar URL

#### 11.3 Polish
- [ ] Smooth animations on notch expand/collapse
- [ ] Boot animation (pop effect)
- [ ] Loading states
- [ ] Error handling / user feedback
- [ ] App icon finalization

---

### Phase 12: Release Prep (Day 9-10)

#### 12.1 Security Rules
- [ ] Update Firestore security rules (see doc above)
- [ ] Update Realtime DB security rules
- [ ] Test rules work correctly

#### 12.2 Final Cleanup
- [ ] Remove test code / print statements
- [ ] Verify no hardcoded test data
- [ ] Update version number
- [ ] Update README

#### 12.3 Build & Test
- [ ] Archive build
- [ ] Test on fresh Mac (no prior data)
- [ ] Verify all flows work

---

## Implementation Phases (Summary)

### v1.1 - Privacy & Polish
- [ ] Hidden apps list (never share these bundle IDs)
- [ ] Invisible mode (pause sharing)
- [ ] Window title sharing (opt-in toggle)
- [ ] Improved animations
- [ ] Sound on friend online (optional)

### v1.2 - Browser & Advanced
- [ ] Browser URL/domain tracking (AppleScript)
- [ ] Multiple lobbies/groups
- [ ] Block/remove friends
- [ ] Stats (hours overlapped with friends)

### Future Ideas
- [ ] iOS companion app (view-only)
- [ ] Focus/DND mode integration
- [ ] "Join" button (open same app as friend)
- [ ] Streak tracking

---

## Claude-Island Architecture Study

### Project Structure (Patterns to Adopt)

```
ClaudeIsland/
├── App/              # Entry point, main app logic
├── Core/             # Business logic
│   ├── NotchViewModel.swift      # State management for notch UI
│   ├── NotchGeometry.swift       # Positioning calculations
│   ├── NotchActivityCoordinator.swift
│   ├── Settings.swift
│   ├── ScreenSelector.swift
│   └── Ext+NSScreen.swift
├── Models/           # Data structures
├── Services/         # Backend communication
│   ├── Hooks/        # Unix socket server
│   ├── Session/      # Session management
│   ├── State/        # App state
│   └── Window/       # Window management
├── UI/
│   ├── Components/   # Reusable UI pieces
│   │   ├── ActionButton.swift
│   │   ├── NotchShape.swift
│   │   ├── StatusIcons.swift
│   │   └── ProcessingSpinner.swift
│   ├── Views/        # Screen layouts
│   └── Window/       # Window configuration
└── Utilities/        # Helpers, extensions
```

### Key Implementation Details

#### NotchViewModel State Machine

```swift
enum NotchStatus { case closed, opened, popping }
enum NotchOpenReason { case click, hover, notification, boot, unknown }
enum NotchContentType { case instances, menu, chat(SessionState) }

@Observable
class NotchViewModel {
    var status: NotchStatus
    var openReason: NotchOpenReason
    var contentType: NotchContentType
    var isHovering: Bool

    // Key behaviors:
    // - 1 second hover delay before auto-expand
    // - "Sticky" state: closing saves current view, reopening restores it
    // - Boot animation: expand briefly then collapse
}
```

#### NotchGeometry Positioning

```swift
struct NotchGeometry {
    let deviceNotchRect: CGRect
    let screenRect: CGRect

    var notchScreenRect: CGRect {
        CGRect(
            x: screenRect.midX - deviceNotchRect.width / 2,
            y: screenRect.maxY - deviceNotchRect.height,
            width: deviceNotchRect.width,
            height: deviceNotchRect.height
        )
    }
}
```

#### Unix Domain Socket Pattern (for future local IPC if needed)

```swift
// Socket at /tmp/app-name.sock
serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

// GCD DispatchSource for non-blocking I/O
let source = DispatchSource.makeReadSource(fileDescriptor: serverSocket)
source.setEventHandler { /* handle incoming connection */ }
```

### UI Components to Adopt/Adapt

| Claude-Island Component | Our Equivalent | Purpose |
|------------------------|----------------|---------|
| `NotchShape.swift` | `FriendsNotchShape` | Custom notch outline |
| `StatusIcons.swift` | `PresenceIndicator` | Online/offline/away dots |
| `ActionButton.swift` | `LobbyActionButton` | Settings, close buttons |
| `ProcessingSpinner.swift` | `SyncingIndicator` | Show when syncing |

### Patterns to Adopt

1. **Observable ViewModel** - Use `@Observable` for reactive state
2. **Geometry as separate struct** - Clean separation of layout math
3. **Content types as enum** - Easy state switching between views
4. **Hover delay** - 1 second before expanding (prevents accidental triggers)
5. **Sticky state** - Remember last view when reopening

---

## References

- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) - Notch UI framework
- [claude-island](https://github.com/farouqaldori/claude-island) - Original inspiration
- [Atoll](https://github.com/Ebullioscopic/Atoll) - Alternative notch framework
- [Firebase Presence](https://firebase.google.com/docs/firestore/solutions/presence)
- [Supabase Presence](https://supabase.com/docs/guides/realtime/presence)
- [NSWorkspace Docs](https://developer.apple.com/documentation/appkit/nsworkspace)
- [AppleScript Browser URLs Gist](https://gist.github.com/vitorgalvao/5392178)

---

## Pushbacks & Suggestions

### Pushbacks (Things to Consider)

1. **Firebase over self-hosted Postgres for MVP**
   - Firebase has built-in `onDisconnect()` - automatically marks users offline when they quit or lose connection
   - With Postgres you'd need heartbeat polling + cleanup cron jobs
   - **Recommendation**: Start with Firebase, migrate later if needed

2. **Porting claude-island vs DynamicNotchKit**
   - claude-island's code is tailored for Claude Code sessions (permission dialogs, chat history)
   - DynamicNotchKit is generic but less control
   - **Recommendation**: Study claude-island's patterns (NotchViewModel, geometry) but evaluate DynamicNotchKit's API first - might save time

3. **Window title in MVP?**
   - Pro: Much more useful ("Figma - Dashboard.fig" vs just "Figma")
   - Con: Window title comes from same `NSRunningApplication` - minimal extra work
   - **Recommendation**: Include it in MVP, it's basically free

4. **"Same app" notifications could be noisy**
   - If 3 friends are in Slack, you get 3 notifications?
   - **Recommendation**: Group them ("Alice, Bob, and Charlie are in Slack") or only notify on first match

### Ideas to Add

1. **App icons** - Show actual app icon next to friend's activity (way more scannable than text)
   ```swift
   NSRunningApplication.icon // Already available!
   ```

2. **Subtle audio cue** - Like Discord's join sound when friend comes online
   - Make it optional, off by default

3. **"Focus" status** - Not invisible, but shows "Deep Work" instead of app name
   - Signals "don't disturb" without hiding completely

4. **Quick copy** - Click friend's URL (when implemented) to copy it
   - "Alice is on github.com/repo/pr/123" → click to copy

5. **Relative time** - "Active now" vs "2m ago" vs "Last seen 1h ago"
   - More human than timestamps

6. **Empty state** - When you have 0 friends, make it easy to share your link
   - Big "Invite Friends" button, copy link, QR code?

7. **Presence indicator colors**:
   - 🟢 Green = Active (app changed in last 2 min)
   - 🟡 Yellow = Idle (no change in 5+ min)
   - ⚫ Gray = Offline

---

## Session Notes

_Add notes from planning sessions here_

### Session 1 (2025-12-23)
- Initial brainstorm
- User confirmed: cloud-based, 10+ friends, macOS only, Google/Apple auth
- Privacy: can hide apps, can go invisible, no pre-approval needed
- UI: green dot compact, expand to list on click, notifications on changes

### Session 2 (2025-12-23)
- Full pivot confirmed: remove time tracking entirely
- Decisions locked: Firebase, mutual friend requests, notch-only UI
- MVP scope: Auth, Activity tracking, Friend system, Notch UI, Notifications
- Deferred: Browser URLs, hidden apps, invisible mode, multiple lobbies

### Session 3 (2025-12-23) - Deep Dive
- Decided: Port claude-island patterns (NotchViewModel, geometry) + study DynamicNotchKit for edge cases
- Decided: Gut existing codebase, rebuild fresh (keep bundle ID)
- Decided: App name + window title + app icon in MVP
- Decided: 2-second debounce for activity changes
- Added: Detailed code implementations for all key components
- Added: Step-by-step implementation checklist (100+ tasks)
- Research completed:
  - Window title via CGWindowListCopyWindowInfo
  - Non-notch Mac detection via NSScreen.auxiliaryTopLeftArea
  - NSWindow configuration for notch overlay
  - NSTrackingArea for hover detection
  - Firebase Auth for macOS (Google + Apple Sign-In)
  - Deep link handling via URL schemes
  - Unique username with Firestore transactions

---

## Quick Reference

### Key APIs
| Purpose | API |
|---------|-----|
| Frontmost app | `NSWorkspace.shared.frontmostApplication` |
| App change | `NSWorkspace.didActivateApplicationNotification` |
| Window title | `CGWindowListCopyWindowInfo` |
| App icon | `NSRunningApplication.icon` |
| Notch detection | `NSScreen.auxiliaryTopLeftArea/Right` |
| Mouse hover | `NSTrackingArea` |
| Window level | `NSWindow.Level.popUpMenu` |
| Presence | Firebase Realtime DB + `onDisconnect()` |
| Profiles | Firestore |
| Auth | Firebase Auth (Google, Apple) |
| Deep links | `CFBundleURLSchemes` + `onOpenURL` |

### Firebase Structure
```
Realtime DB:
  /presence/{uid} → online, lastSeen, appName, windowTitle

Firestore:
  /users/{uid} → displayName, username, avatarURL
  /usernames/{username} → uid (for uniqueness)
  /friends/{orderedUidPair} → users[], status
  /friendRequests/{recipientUid}/incoming/{senderUid}
```

### Notch States
```
closed → (hover 1s) → opened
closed → (click) → opened
closed → (notification) → opened → (auto 3s) → closed
opened → (click outside) → closed
opened → (mouse exit if hover-opened) → closed
boot → popping → (1.5s) → closed
```
