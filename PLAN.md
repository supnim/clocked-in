# Clocked-In - Complete Implementation Plan

## Overview

A macOS presence app that lives in the notch, showing friends what you're working on in real-time with activity history timelines.

---

## All Finalized Decisions

| Topic | Decision |
|-------|----------|
| **Auth** | ~~Username to start (Google auth available but simpler with handle)~~ **Shipped differently:** device-UUID generated on first run and registered with the backend immediately; username is picked *after* that (still blocking, but no longer the very first step). See "Shipped Differently" below. |
| **Identity** | UUID (permanent) + username (changeable handle) |
| **Username rules** | 3-20 chars, `a-z`, `0-9`, `_`, lowercase only |
| **Display name** | Username IS the display name (no separate field) |
| **Username picker** | Inside the notch (first time opening) |
| **Username validation** | On blur / submit only (not real-time debounce) |
| **Force username** | Can't use app until username is picked (notch stays closed) |
| **Idle → Away** | 15 minutes of inactivity |
| **Custom status** | Yes, user can set their own status message |
| **Notifications** | Show actual app icons, silent (no sound) |
| **Notification duration** | 3 seconds, latest only (no queue) |
| **Tap notification** | Opens that friend's expanded view |
| **Friend limits** | Unlimited, scrollable list |
| **Friend model** | Mutual (request → accept) |
| **Friend visibility** | Only after both accept |
| **Friend search** | Fuzzy search by username |
| **Notch expand** | Expand button next to "You" row (~800px) |
| **"You" row** | Always sticky at bottom (friends scroll above) |
| **No friends state** | Show your timeline + empty friends message + add button |
| **App colors** | Hash bundle ID → HSL color |
| **System apps** | Track everything (including Finder, etc.) |
| **Multiple Macs** | Not supported for MVP (last active wins) |
| **Offline mode** | "Offline" banner + cached friends list |
| **Timezone** | Store UTC, display in user's local timezone |
| **Account deletion** | Not in MVP |
| **First friend** | Simple "You're connected!" toast |
| **App icon storage** | Cache locally + sync base64 to Firebase |

---

## Shipped Differently

A few decisions above changed shape during implementation:

- **Auth is device-UUID-first, not username-first.** On first launch the app
  generates a UUID, stores it in Keychain, and registers it with the backend
  (`POST /auth/device`) before any username exists. The username picker still
  blocks the notch afterward — see `Force username` above — but it's the
  second step, not the first.
- **Google auth is browser-redirect OAuth, not in-app.** `GET /auth/google`
  redirects to Google's consent screen; `GET /auth/callback` handles the
  exchange and redirects back into the app via `clockedin://auth?token=...`.
  It is not a native in-app sign-in sheet.
- **Timeline / history features were cut from v1** — see the "v1.1 /
  Post-launch" section near the end of this document.

---

## Feature Specifications

### 1. Authentication & Identity

#### First Launch Flow
```
App Launch
    ↓
Check Keychain for UUID
    ↓
[No UUID] ────────────────────────────────┐
    ↓                                      │
Generate UUID                              │
Store in Keychain                          │
    ↓                                      │
Open Notch with Username Picker            │
(Notch CANNOT be closed until             │
username is picked)                        │
    ↓                                      │
User types username                        │
    ↓                                      │
On Submit: Check Firestore availability    │
    ↓                                      │
[Available] ─────────┐                     │
    ↓                │                     │
Create /users/{uid}  │                     │
Create /usernames/{username}               │
    ↓                                      │
Main UI ←────────────┴─────────────────────┘
                                           │
[Has UUID] ────────────────────────────────┘
    ↓
Fetch user from Firestore
    ↓
Main UI
```

#### Username Rules (Enforced)
- **Length:** 3-20 characters
- **Allowed chars:** `a-z`, `0-9`, `_`
- **Case:** Force lowercase (convert on input)
- **Validation regex:** `^[a-z0-9_]{3,20}$`
- **Reserved words:** Block "admin", "system", "clocked", "clockedin", etc.

#### Username Validation Messages
| State | Message |
|-------|---------|
| Too short | "Username must be at least 3 characters" |
| Too long | "Username must be 20 characters or less" |
| Invalid chars | "Only letters, numbers, and underscores allowed" |
| Checking | "Checking availability..." |
| Available | "✓ Available!" (green) |
| Taken | "✗ Username is taken" (red) |
| Reserved | "✗ This username is reserved" (red) |

#### Keychain Storage
```swift
// Store
KeychainService.save(key: "user_uuid", value: uuid)

// Retrieve
let uuid = KeychainService.get(key: "user_uuid")
```

---

### 2. Activity Tracking

#### What We Track Per Session
| Field | Type | Description |
|-------|------|-------------|
| `id` | String | UUID for session |
| `appName` | String | Localized app name |
| `bundleId` | String | e.g., "com.apple.dt.Xcode" |
| `startTime` | Date | When session started (UTC) |
| `endTime` | Date? | When session ended (UTC), nil if active |
| `windowTitles` | [String]? | If privacy setting allows |
| `browserDomains` | [String]? | If privacy setting allows |

#### Session Lifecycle
```
App Switch Detected (NSWorkspace notification)
    ↓
Close current session (set endTime = now)
Save to Firestore: /users/{uid}/activity/{sessionId}
    ↓
Start new session (startTime = now, endTime = nil)
Update Realtime DB presence
    ↓
[If hidden app] → Set status = "ghost", don't share app name
```

#### Session Close Triggers
| Trigger | Action |
|---------|--------|
| App switch | Close old, start new |
| Mac sleep | Close current (NSWorkspace.willSleepNotification) |
| Mac wake | Start new for frontmost app |
| App quit | Close current (applicationWillTerminate) |
| Idle 15 min | Keep session open, change status to "away" |
| App crash | Next launch: check for orphan sessions, close them |

#### Orphan Session Cleanup
On app launch:
1. Query Firestore for sessions where `endTime == nil` and `startTime < 24 hours ago`
2. Set `endTime = startTime + 1 hour` (reasonable default)
3. Log warning for debugging

#### Activity Aggregation (30-day rule)
**Cut from v1 — moved to "v1.1 / Post-launch" section.** This only matters
once the Timeline feature exists to consume it.

---

### 3. Presence System

#### Presence States
| State | Color | Condition |
|-------|-------|-----------|
| `online` | Green ● | Active in last 15 min |
| `away` | Yellow ● | Idle 15+ min, app still running |
| `offline` | Gray ○ | App closed / disconnected |
| `ghost` | Purple 👻 | Using hidden app |

#### Idle Detection
```swift
// Use EventMonitor to track mouse/keyboard
var lastActivityTime: Date = Date()

// On any mouse move or key press:
lastActivityTime = Date()

// Timer every 60 seconds:
if Date().timeIntervalSince(lastActivityTime) > 900 { // 15 min
    setPresenceStatus(.away)
} else {
    setPresenceStatus(.online)
}
```

#### Realtime DB Presence Structure
```
/presence/{uid}/
├── online: true
├── status: "online" | "away" | "offline" | "ghost"
├── appName: "Xcode" (null if ghost)
├── appBundleId: "com.apple.dt.Xcode" (null if ghost)
├── appIconBase64: "iVBORw0KGgo..." (32x32 PNG)
├── windowTitle: "Project.swift" (null if disabled)
├── browserDomain: "github.com" (null if disabled)
├── sessionStart: 1703520000000 (timestamp)
├── statusMessage: "Working on clocked-in"
├── lastSeen: 1703523600000 (timestamp)
└── updatedAt: 1703523600000 (timestamp)
```

#### onDisconnect Handler
```swift
// Set up when going online
presenceRef.onDisconnectSetValue([
    "online": false,
    "status": "offline",
    "appName": nil,
    "appBundleId": nil,
    "lastSeen": ServerValue.timestamp()
])
```

---

### 4. Friends System

#### Friendship Document Structure
```
/friendships/{uid1_uid2}/
├── id: "abc123_xyz789" (sorted UIDs joined with _)
├── users: ["abc123", "xyz789"]
├── status: "pending" | "accepted" | "declined"
├── requestedBy: "abc123"
├── createdAt: Timestamp
└── acceptedAt: Timestamp (null if pending)
```

#### Friend Request Flow
```
User A searches "@lucas"
    ↓
FriendService.searchUsers(query: "lucas")
Returns matching users (fuzzy search)
    ↓
User A taps [Add] on Lucas
    ↓
FriendService.sendRequest(toUid: lucasUid)
Creates /friendships/{sorted_uids} with status: "pending"
    ↓
Lucas sees notification badge on 🔔
    ↓
Lucas opens Pending Requests
    ↓
Lucas taps [Accept]
    ↓
FriendService.acceptRequest(fromUid: userAUid)
Updates status: "accepted", sets acceptedAt
    ↓
Both users now see each other in friends list
Show toast: "You're connected with Lucas!"
```

#### Fuzzy Search Implementation
```swift
func searchUsers(query: String) async throws -> [User] {
    // Firestore doesn't support fuzzy search natively
    // Option 1: Prefix search (simple)
    let snapshot = try await db.collection("users")
        .whereField("username", isGreaterThanOrEqualTo: query.lowercased())
        .whereField("username", isLessThan: query.lowercased() + "\u{f8ff}")
        .limit(to: 20)
        .getDocuments()

    // Filter out self and existing friends
    return snapshot.documents.compactMap { ... }
}
```

#### "Currently With" Detection
```swift
// When building friends list:
var appToFriends: [String: [FriendPresence]] = [:]

for friend in onlineFriends {
    let bundleId = friend.presence.appBundleId ?? ""
    appToFriends[bundleId, default: []].append(friend)
}

// For each friend, check if others are in same app
for friend in friends {
    let bundleId = friend.presence.appBundleId ?? ""
    let others = appToFriends[bundleId]?.filter { $0.uid != friend.uid } ?? []
    if !others.isEmpty {
        friend.currentlyWith = others.map { $0.user.username }
    }
}
```

---

### 5. Privacy & Ghost Mode

#### Privacy Settings Structure
```
/users/{uid}/settings/privacy
├── hiddenBundleIds: ["com.tinder.Tinder", "com.apple.MobileSMS"]
├── shareWindowTitles: true
├── shareBrowserURLs: true
└── invisibleMode: false
```

#### Ghost Mode Logic
```swift
func updatePresence(for activity: Activity) {
    let settings = PrivacySettings.shared

    // Full invisible mode - appear offline
    if settings.invisibleMode {
        setPresenceStatus(.offline)
        return
    }

    // Hidden app - show ghost
    if settings.hiddenBundleIds.contains(activity.bundleId) {
        updatePresence(
            status: .ghost,
            appName: nil,
            appBundleId: nil,
            appIcon: nil
        )
        return
    }

    // Normal - share everything allowed
    updatePresence(
        status: .online,
        appName: activity.appName,
        appBundleId: activity.bundleId,
        appIcon: activity.appIconBase64,
        windowTitle: settings.shareWindowTitles ? activity.windowTitle : nil,
        browserDomain: settings.shareBrowserURLs ? activity.browserDomain : nil
    )
}
```

#### Hidden Apps Picker UI
```
┌─────────────────────────────────────────┐
│  ← Hidden Apps                     [×]  │
├─────────────────────────────────────────┤
│  Apps you hide will show as "Ghost     │
│  Mode" to your friends.                 │
│                                         │
│  🔍 Search apps...                      │
│                                         │
│  Currently Hidden (3):                  │
│  ┌─────────────────────────────────────┐│
│  │ ◉ Tinder              [Remove]     ││
│  │ ◉ Messages            [Remove]     ││
│  │ ◉ Discord             [Remove]     ││
│  └─────────────────────────────────────┘│
│                                         │
│  Recently Used:                         │
│  ┌─────────────────────────────────────┐│
│  │ ◉ Xcode                    [Hide]  ││
│  │ ◉ Chrome                   [Hide]  ││
│  │ ◉ Slack                    [Hide]  ││
│  │ ◉ Figma                    [Hide]  ││
│  └─────────────────────────────────────┘│
└─────────────────────────────────────────┘
```

---

### 6. Notifications (Closed Notch)

#### Notification Trigger Logic
```swift
// In PresenceListener, when friend presence changes:
func handlePresenceChange(friend: FriendPresence, oldPresence: Presence?, newPresence: Presence) {
    // Only notify if user is active
    guard isUserActive() else { return }

    // Only notify for app changes (not just lastSeen updates)
    guard oldPresence?.appBundleId != newPresence.appBundleId else { return }

    // Don't notify for offline transitions
    guard newPresence.status != .offline else { return }

    // Show notification
    NotchNotificationManager.shared.show(
        friend: friend,
        oldApp: oldPresence?.appIconBase64,
        newApp: newPresence.appIconBase64
    )
}

func isUserActive() -> Bool {
    return Date().timeIntervalSince(lastActivityTime) < 900 // 15 min
}
```

#### Notification UI Component
```swift
struct AppChangeNotification: View {
    let friend: FriendPresence
    let oldAppIcon: Data?
    let newAppIcon: Data?

    var body: some View {
        HStack(spacing: 8) {
            // Friend avatar (small)
            AvatarView(user: friend.user, size: 20)

            // Old app icon
            if let oldIcon = oldAppIcon {
                AppIconView(data: oldIcon, size: 16)
            }

            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // New app icon
            if let newIcon = newAppIcon {
                AppIconView(data: newIcon, size: 16)
            }

            // Friend name
            Text(friend.user.username)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
    }
}
```

#### Notification Animation
```swift
// Show notification
withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
    showNotification = true
}

// Auto-dismiss after 3 seconds
DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
    withAnimation(.easeOut(duration: 0.2)) {
        showNotification = false
    }
}
```

---

### 7. Custom Status

#### Status in Presence
```swift
// Update status message
func setStatusMessage(_ message: String?) {
    let presenceRef = Database.database().reference(withPath: "presence/\(uid)")
    presenceRef.updateChildValues(["statusMessage": message ?? NSNull()])

    // Also save to Firestore for persistence
    Firestore.firestore().collection("users").document(uid).updateData([
        "statusMessage": message ?? FieldValue.delete()
    ])
}
```

#### Status Presets
```swift
let statusPresets = [
    "Focusing",
    "In a meeting",
    "AFK",
    "Do not disturb",
    "Taking a break"
]
```

#### Status UI
```
┌─────────────────────────────────────────┐
│  Edit Status                       [×]  │
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────────┐│
│  │ Working on clocked-in         [×]  ││
│  └─────────────────────────────────────┘│
│                                         │
│  Quick Status:                          │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│  │Focusing │ │Meeting  │ │  AFK    │   │
│  └─────────┘ └─────────┘ └─────────┘   │
│  ┌─────────┐ ┌─────────┐               │
│  │  DND    │ │ Break   │               │
│  └─────────┘ └─────────┘               │
│                                         │
│  ┌─────────────────────────────────────┐│
│  │           Clear Status             ││
│  └─────────────────────────────────────┘│
└─────────────────────────────────────────┘
```

---

### 8. Offline Mode

#### Offline Detection
```swift
// Monitor network status
let monitor = NWPathMonitor()
monitor.pathUpdateHandler = { path in
    if path.status == .satisfied {
        isOffline = false
        reconnect()
    } else {
        isOffline = true
    }
}
```

#### Offline UI
```swift
var body: some View {
    VStack {
        if isOffline {
            HStack {
                Image(systemName: "wifi.slash")
                Text("Offline")
            }
            .font(.system(size: 11))
            .foregroundColor(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }

        // Rest of content...
    }
}
```

#### Cached Data
```swift
// Cache friends list locally
func cacheFriendsList(_ friends: [FriendPresence]) {
    let data = try? JSONEncoder().encode(friends)
    UserDefaults.standard.set(data, forKey: "cached_friends")
}

func loadCachedFriends() -> [FriendPresence]? {
    guard let data = UserDefaults.standard.data(forKey: "cached_friends"),
          let friends = try? JSONDecoder().decode([FriendPresence].self, from: data) else {
        return nil
    }
    return friends
}
```

---

## UI States (Complete ASCII Reference)

### 1. Closed Notch - Default
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│                                                          │
└──────────────────────────────────────────────────────────┘
     ● 3
     ↑ green dot + online friend count
```

### 2. Closed Notch - With Notification
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│                                                          │
└──────────────────────────────────────────────────────────┘
     ● 3                              [😀 ◉→◉ lucas]
     ↑ online count                   ↑ notification (3s)
```

### 3. Closed Notch - Offline
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│                                                          │
└──────────────────────────────────────────────────────────┘
     ○ --                              📡 Offline
```

### 4. Username Picker (First Launch)
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│  Welcome to Clocked-In                                  │
├──────────────────────────────────────────────────────────┤
│                                                          │
│         See what your friends are working on            │
│                                                          │
│  Pick your username:                                    │
│  ┌────────────────────────────────────────────────────┐ │
│  │ @nimesh                                      ✓     │ │
│  └────────────────────────────────────────────────────┘ │
│  ✓ Available!                                           │
│                                                          │
│  This is how friends will find you.                     │
│  You can change it later in settings.                   │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │              Get Started                           │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### 5. No Friends State
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│  Friends                              [+] [🔔] [⚙] [×]  │
├──────────────────────────────────────────────────────────┤
│                                                          │
│                     👥                                   │
│         Add friends to see what they're up to           │
│                                                          │
│         ┌──────────────────────────────┐                │
│         │      Add Your First Friend   │                │
│         └──────────────────────────────┘                │
│                                                          │
│  Your handle: @nimesh                          [Copy]   │
│  Share this so friends can add you!                     │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  ● You         ◉ Claude       1h 05m           [▼ More] │
│                "Working on clocked-in"                   │
└──────────────────────────────────────────────────────────┘
```

### 6. Friends List (Default Height ~250px)
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│  Friends                              [+] [🔔] [⚙] [×]  │
├──────────────────────────────────────────────────────────┤
│  ● Lucas       ◉ Xcode        2h 15m                    │
│  ● Sarah       ◉ Figma        45m        👥 with Mike   │
│  ● Mike        ◉ Figma        1h 30m     👥 with Sarah  │
│  ○ Alex        offline        3h ago                    │
├──────────────────────────────────────────────────────────┤
│  ● You         ◉ Claude       1h 05m           [▼ More] │
│                "Working on clocked-in"                   │
└──────────────────────────────────────────────────────────┘
```

### 7. Friend Expanded (Accordion)
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│  Friends                              [+] [🔔] [⚙] [×]  │
├──────────────────────────────────────────────────────────┤
│  ▼ Lucas       ◉ Xcode        2h 15m                    │
│  ┌────────────────────────────────────────────────────┐ │
│  │  [Today] [Week] [Month]                            │ │
│  │  ┌──────────────────────────────────────────────┐  │ │
│  │  │██████████ ████████ ██████ ████ █████████████│  │ │
│  │  └──────────────────────────────────────────────┘  │ │
│  │  Xcode 4h • Slack 2h • Chrome 1h • Other 45m      │ │
│  │  Total: 7h 45m                                     │ │
│  │                                     [Remove Friend]│ │
│  └────────────────────────────────────────────────────┘ │
│  ● Sarah       ◉ Figma        45m        👥 with Mike   │
│  ● Mike        ◉ Figma        1h 30m                    │
├──────────────────────────────────────────────────────────┤
│  ● You         ◉ Claude       1h 05m           [▼ More] │
└──────────────────────────────────────────────────────────┘
```

### 8. Expanded Height (~800px)
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│  Friends                              [+] [🔔] [⚙] [×]  │
├──────────────────────────────────────────────────────────┤
│  ● Lucas       ◉ Xcode        2h 15m                    │
│  ● Sarah       ◉ Figma        45m        👥 with Mike   │
│  ● Mike        ◉ Figma        1h 30m     👥 with Sarah  │
│  ● Emma        ◉ VS Code      3h 00m                    │
│  ● James       ◉ Slack        25m                       │
│  ● Anna        ◉ Chrome       1h 10m                    │
│  ● David       ◉ Terminal     4h 30m                    │
│  ○ Alex        offline        3h ago                    │
│  ○ Chris       offline        1d ago                    │
│  ○ Nina        offline        2d ago                    │
│                                                          │
│                    (scrollable)                          │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  ● You         ◉ Claude       1h 05m           [▲ Less] │
│                "Working on clocked-in"                   │
│  ┌────────────────────────────────────────────────────┐ │
│  │  [Today] [Week] [Month]                            │ │
│  │  ┌──────────────────────────────────────────────┐  │ │
│  │  │██████████ ████████ ██████ ████ █████████████│  │ │
│  │  └──────────────────────────────────────────────┘  │ │
│  │  Claude 3h • Xcode 2h • Safari 1h • Other 30m     │ │
│  │  Total: 6h 30m today                              │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### 9. Your Timeline View
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│  ← Your Activity                                   [×]  │
├──────────────────────────────────────────────────────────┤
│  ◉ Claude       1h 05m                                  │
│  "Working on clocked-in"              [Edit Status]     │
│                                                          │
│  [Today] [Week] [Month]                                 │
│  ┌────────────────────────────────────────────────────┐ │
│  │██████████████ ████████████ ██████ ████ ██████████│ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  Today's Apps:                                          │
│  ◉ Claude        3h 15m    ████████████████            │
│  ◉ Xcode         2h 00m    ██████████                  │
│  ◉ Safari        1h 30m    ███████                     │
│  ◉ Slack         45m       ████                        │
│  ◉ Mail          20m       ██                          │
│                                                          │
│  Total: 7h 50m                                          │
│                                                          │
│  💡 You spent 25% less time in Slack this week!        │
└──────────────────────────────────────────────────────────┘
```

### 10. Add Friend View
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│  ← Add Friend                                      [×]  │
├──────────────────────────────────────────────────────────┤
│  🔍 Search username...                                  │
│  ┌────────────────────────────────────────────────────┐ │
│  │ luc                                                │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  Results:                                               │
│  ┌────────────────────────────────────────────────────┐ │
│  │ 😀 @lucas_dev      Lucas Smith              [Add] │ │
│  │ 😀 @lucasart       Lucas Martinez           [Add] │ │
│  │ 😀 @luca           Luca Rossi               [Add] │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ─────────────────────────────────────────────────────  │
│  Your handle: @nimesh                                   │
│  Share link: clockedin://add/nimesh            [Copy]  │
└──────────────────────────────────────────────────────────┘
```

### 11. Pending Requests View
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│  ← Friend Requests (2)                             [×]  │
├──────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────┐ │
│  │ 😀 @sarah_designs   Sarah Chen                    │ │
│  │    Sent 2 hours ago                               │ │
│  │    [Accept]                          [Decline]    │ │
│  └────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────┐ │
│  │ 😀 @mike_codes      Mike Johnson                  │ │
│  │    Sent 1 day ago                                 │ │
│  │    [Accept]                          [Decline]    │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  No more requests                                       │
└──────────────────────────────────────────────────────────┘
```

### 12. Settings View
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│  ← Settings                                        [×]  │
├──────────────────────────────────────────────────────────┤
│  Profile                                                │
│  😀 @nimesh                                             │
│  [Change Username]                                      │
│                                                          │
│  ─────────────────────────────────────────────────────  │
│  Privacy                                                │
│  [●] Share Window Titles                                │
│  [●] Share Browser URLs                                 │
│  [ ] Invisible Mode                                     │
│                                                          │
│  Hidden Apps (3)                              [Manage]  │
│  Tinder, Messages, ...                                  │
│                                                          │
│  ─────────────────────────────────────────────────────  │
│  General                                                │
│  [●] Launch at Login                                    │
│                                                          │
│  ─────────────────────────────────────────────────────  │
│  [Sign Out]                              v1.0.0        │
└──────────────────────────────────────────────────────────┘
```

### 13. Change Username View
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│  ← Change Username                                 [×]  │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Current: @nimesh                                       │
│                                                          │
│  New username:                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ @nimesh_dev                                  ✓     │ │
│  └────────────────────────────────────────────────────┘ │
│  ✓ Available!                                           │
│                                                          │
│  ⚠️  Friends will need to find you by your new handle.  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │              Save Changes                          │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### 14. Edit Status View
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│  ← Edit Status                                     [×]  │
├──────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────┐ │
│  │ Working on clocked-in                         [×] │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  Quick Status:                                          │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐                   │
│  │Focusing │ │Meeting  │ │  AFK    │                   │
│  └─────────┘ └─────────┘ └─────────┘                   │
│  ┌─────────┐ ┌─────────┐                               │
│  │  DND    │ │ Break   │                               │
│  └─────────┘ └─────────┘                               │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │              Clear Status                          │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### 15. Hidden Apps Manager
```
┌─────────────────────────[NOTCH]─────────────────────────┐
│  ← Hidden Apps                                     [×]  │
├──────────────────────────────────────────────────────────┤
│  Apps you hide will show as "Ghost Mode 👻"            │
│  to your friends.                                       │
│                                                          │
│  🔍 Search apps...                                      │
│                                                          │
│  Currently Hidden:                                      │
│  ┌────────────────────────────────────────────────────┐ │
│  │ ◉ Tinder                            [Unhide]      │ │
│  │ ◉ Messages                          [Unhide]      │ │
│  │ ◉ Discord                           [Unhide]      │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  Recently Used:                                         │
│  ┌────────────────────────────────────────────────────┐ │
│  │ ◉ Xcode                               [Hide]      │ │
│  │ ◉ Chrome                              [Hide]      │ │
│  │ ◉ Slack                               [Hide]      │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

---

## Data Models (Swift)

```swift
import Foundation
import FirebaseFirestore

// MARK: - User

struct User: Codable, Identifiable {
    @DocumentID var id: String?
    var username: String            // 3-20 chars, lowercase, unique
    var statusMessage: String?
    var createdAt: Date
    var updatedAt: Date

    // Username IS display name, no separate field
    var displayName: String { username }
}

// MARK: - Username Reservation

struct UsernameReservation: Codable {
    let uid: String
    let createdAt: Date
}

// MARK: - Presence (Realtime DB)

struct Presence: Codable {
    var online: Bool
    var status: PresenceStatus
    var appName: String?
    var appBundleId: String?
    var appIconBase64: String?
    var windowTitle: String?
    var browserDomain: String?
    var sessionStart: Date?
    var statusMessage: String?
    var lastSeen: Date
    var updatedAt: Date
}

enum PresenceStatus: String, Codable {
    case online
    case away
    case offline
    case ghost
}

// MARK: - Activity Session

struct ActivitySession: Codable, Identifiable {
    @DocumentID var id: String?
    let appName: String
    let bundleId: String
    let startTime: Date
    var endTime: Date?
    var windowTitles: [String]?
    var browserDomains: [String]?

    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }
}

// MARK: - Daily Summary
// Cut from v1 along with the Timeline feature — see "v1.1 / Post-launch" below.

// MARK: - Friendship

struct Friendship: Codable, Identifiable {
    @DocumentID var id: String?     // Format: "uid1_uid2" (sorted)
    let users: [String]
    var status: FriendshipStatus
    let requestedBy: String
    let createdAt: Date
    var acceptedAt: Date?
}

enum FriendshipStatus: String, Codable {
    case pending
    case accepted
    case declined
}

// MARK: - Friend Presence (Combined for UI)

struct FriendPresence: Identifiable {
    let uid: String
    let user: User
    let presence: Presence
    var currentlyWith: [String]?    // Usernames of friends in same app

    var id: String { uid }

    var status: PresenceStatus {
        presence.status
    }

    var isOnline: Bool {
        presence.online && presence.status != .offline
    }
}

// MARK: - Privacy Settings

struct PrivacySettings: Codable {
    var hiddenBundleIds: [String]
    var shareWindowTitles: Bool
    var shareBrowserURLs: Bool
    var invisibleMode: Bool

    static let `default` = PrivacySettings(
        hiddenBundleIds: [],
        shareWindowTitles: true,
        shareBrowserURLs: true,
        invisibleMode: false
    )
}

// MARK: - Timeline / Insights
// Cut from v1 — see "v1.1 / Post-launch" below for the original TimelineData,
// AppTimelineEntry, TimelinePeriod, and Insight models.

// MARK: - App Info (for hidden apps picker)

struct AppInfo: Identifiable, Hashable {
    let bundleId: String
    let name: String
    let icon: Data?

    var id: String { bundleId }
}
```

---

## Firebase Structure

```
Realtime Database:
└── presence/
    └── {uid}/
        ├── online: true
        ├── status: "online"
        ├── appName: "Xcode"
        ├── appBundleId: "com.apple.dt.Xcode"
        ├── appIconBase64: "iVBORw0KGgo..."
        ├── windowTitle: "Project.swift"
        ├── browserDomain: "github.com"
        ├── sessionStart: 1703520000000
        ├── statusMessage: "Working on clocked-in"
        ├── lastSeen: 1703523600000
        └── updatedAt: 1703523600000

Firestore:
├── users/
│   └── {uid}/
│       ├── username: "nimesh"
│       ├── statusMessage: "Building cool stuff"
│       ├── createdAt: Timestamp
│       └── updatedAt: Timestamp
│
├── usernames/
│   └── {username}/
│       ├── uid: "{uid}"
│       └── createdAt: Timestamp
│
├── users/{uid}/activity/
│   └── {sessionId}/
│       ├── appName: "Xcode"
│       ├── bundleId: "com.apple.dt.Xcode"
│       ├── startTime: Timestamp
│       ├── endTime: Timestamp
│       └── windowTitles: ["main.swift", "App.swift"]
│
├── users/{uid}/summaries/
│   └── {YYYY-MM-DD}/
│       ├── date: "2024-01-15"
│       ├── apps: [{appName, bundleId, totalTime, sessionCount}]
│       └── totalTime: 28800
│
├── users/{uid}/settings/
│   └── privacy/
│       ├── hiddenBundleIds: ["com.tinder.Tinder"]
│       ├── shareWindowTitles: true
│       ├── shareBrowserURLs: true
│       └── invisibleMode: false
│
└── friendships/
    └── {uid1_uid2}/      (UIDs sorted alphabetically)
        ├── users: ["uid1", "uid2"]
        ├── status: "accepted"
        ├── requestedBy: "uid1"
        ├── createdAt: Timestamp
        └── acceptedAt: Timestamp
```

---

## Implementation Phases

### Phase 1: Identity & Auth
**Files to create/modify:**
- `Services/Auth/IdentityService.swift` - UUID generation, Keychain storage
- `Services/Auth/UsernameService.swift` - Username validation, availability check
- `UI/Views/UsernamePickerView.swift` - First launch picker inside notch
- `Core/Notch/NotchViewModel.swift` - Add state for username picker

**Tasks:**
1. Generate UUID on first launch using `UUID().uuidString`
2. Store UUID in Keychain using Security framework
3. Create UsernamePickerView with text field and validation
4. Implement real-time availability check against Firestore `/usernames/{username}`
5. On submit: Create `/users/{uid}` and `/usernames/{username}` atomically (batch write)
6. Block notch from closing until username is set
7. On subsequent launches: Check Keychain for UUID, fetch user from Firestore

### Phase 2: Activity Tracking
**Files to create/modify:**
- `Core/Activity/ActivitySessionManager.swift` - Session lifecycle
- `Services/Firebase/ActivityService.swift` - Firestore activity operations
- `Core/Activity/IdleDetector.swift` - Mouse/keyboard activity monitoring

**Tasks:**
1. Refactor ActivityMonitor to track sessions (start/end times)
2. Create ActivitySession on app switch, close previous session
3. Save sessions to Firestore `/users/{uid}/activity/{sessionId}`
4. Implement idle detection (15 min → Away status)
5. Handle Mac sleep/wake (NSWorkspace notifications)
6. Implement orphan session cleanup on app launch
7. Create daily aggregation for sessions > 30 days old

### Phase 3: Presence & Friends
**Files to modify:**
- `Core/Presence/PresenceManager.swift` - Add app icon sync
- `Core/Presence/PresenceListener.swift` - Add "currently with" detection
- `UI/Components/FriendRow.swift` - Redesign with new layout
- `UI/Views/LobbyView.swift` - Add accordion expand

**Tasks:**
1. Sync app icon (32x32 base64) to Realtime DB on activity change
2. Detect friends using same app ("currently with")
3. Redesign friend row to show: status, app icon, app name, duration, currently with
4. Implement accordion expand/collapse for friend timeline
5. Add custom status message support
6. Sticky "You" row at bottom

### Phase 4: Notifications
**Files to create/modify:**
- `Core/Notifications/NotchNotificationManager.swift` - Notification display logic
- `UI/Components/AppChangeNotification.swift` - Notification UI
- `UI/NotchContent/CompactNotchView.swift` - Add notification display area

**Tasks:**
1. Listen for friend presence changes in PresenceListener
2. Detect app changes (compare old vs new bundleId)
3. Check if user is active (last activity < 15 min)
4. Show notification with friend avatar, old icon → new icon
5. Auto-dismiss after 3 seconds
6. Tap notification → open friend's expanded view

### Phase 5: UI Polish
**Files to modify:**
- `UI/NotchContent/NotchContentView.swift` - Dynamic height
- `UI/NotchContent/CompactNotchView.swift` - Online count, notifications
- All view files - Animations and transitions

**Tasks:**
1. Closed notch: Show "● N" online count on left
2. Closed notch: Show notification on right
3. Add expand/collapse button (`[▼ More]` / `[▲ Less]`)
4. Implement dynamic notch height (250px default, 800px expanded)
5. Add smooth animations for all transitions
6. Implement offline banner

### Phase 6: Edge Cases & Polish
**Tasks:**
1. Offline mode: Cache friends list, show offline banner
2. Error handling: Show appropriate error messages
3. Loading states: Skeleton loaders where appropriate
4. Empty states: Friendly messages and CTAs
5. Performance: Optimize Firestore queries, reduce re-renders
6. Memory: Clean up listeners on deinit

---

## Testing Checklist

### Identity & Auth
- [ ] First launch shows username picker
- [ ] Cannot close notch without picking username
- [ ] Username validation works (length, chars, availability)
- [ ] UUID persists across app restarts
- [ ] Returning user auto-logs in

### Activity Tracking
- [ ] App switches create new sessions
- [ ] Sessions have correct start/end times
- [ ] Mac sleep closes current session
- [ ] Idle detection triggers "Away" after 15 min
- [ ] Hidden apps show as "Ghost Mode"

### Friends
- [ ] Search finds users by prefix
- [ ] Friend request flow works (send → accept)
- [ ] "Currently with" shows correctly
- [ ] Friend timeline shows their activity

### Notifications
- [ ] Notification shows on friend app change
- [ ] Notification only shows when user is active
- [ ] Notification auto-dismisses after 3s
- [ ] Tapping notification opens friend detail

### UI
- [ ] Notch expands to 800px
- [ ] "You" row stays sticky at bottom
- [ ] Accordion expand/collapse works
- [ ] Offline banner shows when disconnected

---

## v1.1 / Post-launch

The Timeline / history feature (Today/Week/Month usage timelines, accordion
expand, 30-day history, insights) was **cut from v1**. Its code has been
deleted (`TimelineService`, `YourTimelineView`, `ActivitySessionManager`,
`TimelineBar`, `Models/Timeline.swift`). Everything below is preserved as the
spec to pick back up from when this feature is revisited post-launch.

### Activity Aggregation (30-day rule)
Run on app launch (or daily background task):
```
1. Query sessions older than 30 days
2. Group by date (YYYY-MM-DD in user's timezone)
3. For each date:
   - Group by bundleId
   - Sum durations
   - Create DailySummary document
4. Delete raw sessions older than 30 days
```

### Timeline Feature

#### Timeline Data Query
```swift
func getTimeline(for uid: String, period: TimelinePeriod) async throws -> TimelineData {
    let calendar = Calendar.current
    let now = Date()

    let (startDate, endDate): (Date, Date) = switch period {
    case .today:
        (calendar.startOfDay(for: now), now)
    case .week:
        (calendar.date(byAdding: .day, value: -7, to: now)!, now)
    case .month:
        (calendar.date(byAdding: .day, value: -30, to: now)!, now)
    }

    // Query raw sessions for recent data (< 30 days)
    let sessions = try await queryActivitySessions(
        uid: uid,
        from: startDate,
        to: endDate
    )

    // Query summaries for older data (> 30 days, if month view)
    var summaries: [DailySummary] = []
    if period == .month {
        summaries = try await querySummaries(uid: uid, from: startDate, to: endDate)
    }

    // Aggregate into timeline data
    return aggregateTimeline(sessions: sessions, summaries: summaries)
}
```

#### Timeline Aggregation
```swift
struct TimelineData {
    var apps: [AppTimelineEntry]  // Sorted by total time desc
    var totalTime: TimeInterval

    struct AppTimelineEntry {
        let appName: String
        let bundleId: String
        let totalTime: TimeInterval
        let color: Color
        let percentage: Double
    }
}

func aggregateTimeline(sessions: [ActivitySession], summaries: [DailySummary]) -> TimelineData {
    var appTimes: [String: (name: String, time: TimeInterval)] = [:]

    // Add session times
    for session in sessions {
        let duration = session.duration
        appTimes[session.bundleId, default: (session.appName, 0)].time += duration
    }

    // Add summary times
    for summary in summaries {
        for app in summary.apps {
            appTimes[app.bundleId, default: (app.appName, 0)].time += app.totalTime
        }
    }

    let totalTime = appTimes.values.reduce(0) { $0 + $1.time }

    let apps = appTimes.map { bundleId, data in
        AppTimelineEntry(
            appName: data.name,
            bundleId: bundleId,
            totalTime: data.time,
            color: colorForBundleId(bundleId),
            percentage: totalTime > 0 ? data.time / totalTime : 0
        )
    }.sorted { $0.totalTime > $1.totalTime }

    return TimelineData(apps: apps, totalTime: totalTime)
}
```

#### Bundle ID → Color
```swift
func colorForBundleId(_ bundleId: String) -> Color {
    // Create stable hash
    var hasher = Hasher()
    hasher.combine(bundleId)
    let hash = abs(hasher.finalize())

    // Map to hue (0-360)
    let hue = Double(hash % 360) / 360.0

    // Fixed saturation and brightness for consistency
    return Color(hue: hue, saturation: 0.65, brightness: 0.75)
}
```

#### Timeline Bar Component
```swift
struct TimelineBar: View {
    let data: TimelineData
    let height: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(data.apps.prefix(10), id: \.bundleId) { app in
                    Rectangle()
                        .fill(app.color)
                        .frame(width: geometry.size.width * app.percentage)
                }

                // "Other" category if more than 10 apps
                if data.apps.count > 10 {
                    let otherPercentage = data.apps.dropFirst(10).reduce(0) { $0 + $1.percentage }
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: geometry.size.width * otherPercentage)
                }
            }
        }
        .frame(height: height)
        .cornerRadius(4)
    }
}
```

### Activity Insights

#### Insight Types
```swift
enum InsightType {
    case moreTime(app: String, percentChange: Int)      // "40% more time in Slack"
    case lessTime(app: String, percentChange: Int)      // "25% less time in Twitter"
    case mostProductiveDay(day: String, hours: Double)  // "Tuesday was your most productive (9h)"
    case newApp(app: String)                            // "New this week: Cursor"
    case streak(days: Int)                              // "5 day streak!"
    case totalTime(hours: Double)                       // "You tracked 42 hours this week"
}
```

#### Insight Generation
```swift
func generateInsights(current: TimelineData, previous: TimelineData?) -> [Insight] {
    var insights: [Insight] = []

    guard let previous = previous else {
        // First week, just show total
        insights.append(.totalTime(hours: current.totalTime / 3600))
        return insights
    }

    // Compare app times
    for app in current.apps {
        if let prevApp = previous.apps.first(where: { $0.bundleId == app.bundleId }) {
            let change = (app.totalTime - prevApp.totalTime) / prevApp.totalTime
            if change > 0.25 {
                insights.append(.moreTime(app: app.appName, percentChange: Int(change * 100)))
            } else if change < -0.25 {
                insights.append(.lessTime(app: app.appName, percentChange: Int(abs(change) * 100)))
            }
        } else {
            // New app
            insights.append(.newApp(app: app.appName))
        }
    }

    // Limit to 3 insights
    return Array(insights.prefix(3))
}
```

### Data Models

```swift
// MARK: - Daily Summary

struct DailySummary: Codable, Identifiable {
    @DocumentID var id: String?     // Format: "YYYY-MM-DD"
    let date: String
    var apps: [AppSummary]
    var totalTime: TimeInterval
}

struct AppSummary: Codable {
    let appName: String
    let bundleId: String
    var totalTime: TimeInterval
    var sessionCount: Int
}

// MARK: - Timeline

struct TimelineData {
    var apps: [AppTimelineEntry]
    var totalTime: TimeInterval
    var insights: [Insight]
}

struct AppTimelineEntry: Identifiable {
    let appName: String
    let bundleId: String
    let totalTime: TimeInterval
    let color: Color
    let percentage: Double

    var id: String { bundleId }
}

enum TimelinePeriod: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
}

// MARK: - Insights

enum Insight: Identifiable {
    case moreTime(app: String, percent: Int)
    case lessTime(app: String, percent: Int)
    case newApp(app: String)
    case totalTime(hours: Double)

    var id: String {
        switch self {
        case .moreTime(let app, _): return "more_\(app)"
        case .lessTime(let app, _): return "less_\(app)"
        case .newApp(let app): return "new_\(app)"
        case .totalTime: return "total"
        }
    }

    var message: String {
        switch self {
        case .moreTime(let app, let percent):
            return "You spent \(percent)% more time in \(app) this week"
        case .lessTime(let app, let percent):
            return "You spent \(percent)% less time in \(app) this week"
        case .newApp(let app):
            return "New this week: \(app)"
        case .totalTime(let hours):
            return "You tracked \(String(format: "%.1f", hours)) hours this week"
        }
    }
}
```

### Implementation Phase (originally Phase 3)
**Files to create/modify:**
- `Services/Timeline/TimelineService.swift` - Query and aggregate timeline data
- `UI/Components/TimelineBar.swift` - Stacked bar visualization
- `UI/Views/YourTimelineView.swift` - Your activity view
- `Utilities/ColorGenerator.swift` - Bundle ID → Color

**Tasks:**
1. Query activity sessions by date range
2. Aggregate sessions into TimelineData (per-app totals)
3. Implement bundle ID → HSL color generation
4. Create TimelineBar component with colored segments
5. Create period toggle (Today/Week/Month)
6. Display app legend with times
7. Generate and display insights

### Decisions (for reference)
| Topic | Decision |
|-------|----------|
| **Timeline expand** | Accordion (inline expand in list) |
| **Timeline periods** | Today / Week / Month toggle |
| **History depth** | 30 days raw, then merge into daily summaries |

### Testing Checklist
- [ ] Today/Week/Month periods show correct data
- [ ] Timeline bar colors are consistent per app
- [ ] App legend shows correct times
- [ ] Insights generate correctly

---

## Notes for Build Agent

1. **Existing code:** There's existing Firebase, auth, and presence code. Review it first and refactor rather than rewrite from scratch where possible.

2. **@Observable pattern:** Use `@Observable` macro (not ObservableObject) per project conventions.

3. **Singletons:** Use `.shared` pattern for services, access lazily to avoid Firebase init issues.

4. **Firestore batch writes:** Use batch writes for atomic operations (e.g., creating user + username reservation).

5. **Error handling:** Use OSLog for logging, handle errors gracefully in UI.

6. **Animations:** Use spring animations (response: 0.3-0.4, dampingFraction: 0.8) for consistency.

7. **Colors:** Dark theme, use Color.white.opacity() for text hierarchy.

8. **Testing:** The app should work without friends (empty state) and with many friends (scrolling).
