# Debug Workflow

Debug common issues in the Clocked-In app.

## Instructions

When debugging, follow this systematic approach:

### 1. Build Issues
```bash
# Clean and rebuild
xcodebuild clean -scheme clocked-in
rm -rf ~/Library/Developer/Xcode/DerivedData/clocked-in-*
```
Then use `/project:build` to rebuild.

### 2. Firebase Connection Issues
Check these files in order:
1. `Resources/GoogleService-Info.plist` - verify credentials exist
2. `Services/Firebase/FirebaseConfig.swift` - check initialization
3. `Services/Firebase/AuthService.swift` - check auth state

Common fixes:
- Ensure Firebase is initialized in AppDelegate
- Check network permissions in entitlements
- Verify bundle ID matches Firebase console

### 3. Presence Not Syncing
Check data flow:
1. `Core/Activity/ActivityMonitor.swift` - is activity detected?
2. `Core/Presence/PresenceManager.swift` - is upload triggered?
3. `Services/Firebase/RealtimeDBService.swift` - is data sent?

Debug with:
```swift
print("Activity: \(activity)")  // In ActivityMonitor
print("Uploading: \(presence)") // In PresenceManager
```

### 4. Notch Not Appearing
Check:
1. `Core/Notch/NotchGeometry.swift` - screen detection
2. `Core/Notch/NotchWindowController.swift` - window creation
3. `Core/Events/EventMonitors.swift` - mouse tracking

### 5. Console Logs
```bash
# Watch app logs
log stream --predicate 'subsystem == "com.yourcompany.clocked-in"' --level debug
```

## Usage
```
/project:debug firebase    # Firebase-specific debugging
/project:debug notch       # Notch UI debugging
/project:debug presence    # Presence sync debugging
```
