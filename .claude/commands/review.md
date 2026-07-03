# Code Review Checklist

Review code changes for quality, patterns, and potential issues.

## Instructions

When reviewing, check each category:

### Swift Patterns
- [ ] Uses `@Observable` macro (not ObservableObject)
- [ ] Uses `@State` for view-owned observables (not @StateObject)
- [ ] Uses `@ObservationIgnored` for non-reactive properties
- [ ] Uses `async/await` (not completion handlers)
- [ ] Uses `guard` for early returns
- [ ] Uses `Task` with proper cancellation

### Firebase Patterns
- [ ] `onDisconnect` set up before `setValue` for presence
- [ ] Friend doc IDs use sorted UID pairs
- [ ] Errors are handled gracefully (presence is best-effort)
- [ ] Debounce applied to frequent updates (2s)
- [ ] Privacy filters applied before upload

### SwiftUI Patterns
- [ ] Views are small and focused
- [ ] Complex logic in ViewModels, not Views
- [ ] `@Bindable` used for bindings to @Observable
- [ ] `@Environment` for dependency injection
- [ ] Animations use `.spring()` for natural feel

### State Machine (Notch)
- [ ] State transitions use `notchOpen/notchClose/notchPop`
- [ ] Content changes use `showContent(_:)`
- [ ] Hover logic properly cancels pending timers

### Performance
- [ ] No unnecessary redraws (check @ObservationIgnored)
- [ ] Debouncing applied where needed
- [ ] Images use proper caching
- [ ] Lists use LazyVStack for long content

### Security
- [ ] No hardcoded secrets/API keys
- [ ] User data filtered client-side before upload
- [ ] Invisible mode respected everywhere

## Usage
```
/project:review           # Review all staged changes
/project:review --file X  # Review specific file
```
