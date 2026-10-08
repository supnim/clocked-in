# Add New Feature

Scaffold a new feature following project patterns.

## Instructions

When adding a new feature:

### 1. Plan the Feature
Identify which layers need changes:
- **Model**: New data types in `Models/`
- **Service**: Firebase operations in `Services/Firebase/`
- **Core Logic**: Business logic in `Core/`
- **UI**: Views in `UI/Views/`, components in `UI/Components/`

### 2. Create Files Following Patterns

**Model** (if needed):
```swift
// Models/NewFeature.swift
import Foundation

struct NewFeature: Codable, Identifiable {
    let id: String
    // properties
}
```

**Service** (if Firebase involved):
```swift
// Services/Firebase/NewFeatureService.swift
import FirebaseFirestore

@Observable
class NewFeatureService {
    static let shared = NewFeatureService()
    private init() {}

    func fetch() async throws -> [NewFeature] {
        // implementation
    }
}
```

**ViewModel** (if complex state):
```swift
// Core/NewFeature/NewFeatureViewModel.swift
@Observable
class NewFeatureViewModel {
    var items: [NewFeature] = []

    @ObservationIgnored
    private var task: Task<Void, Never>?

    // methods
}
```

**View**:
```swift
// UI/Views/NewFeatureView.swift
import SwiftUI

struct NewFeatureView: View {
    @State private var viewModel = NewFeatureViewModel()

    var body: some View {
        // implementation
    }
}
```

### 3. Wire Up to Notch (if UI feature)
Add to `NotchContentType`:
```swift
case newFeature
```

Add size in `NotchViewModel.openedSize`:
```swift
case .newFeature:
    return CGSize(width: 480, height: 320)
```

Add view in `ExpandedNotchView`.

### 4. Test
- Build: `/project:build`
- Test: `/project:test`
- Manual testing in simulator

## Usage
```
/project:add-feature notifications  # Add notification settings
/project:add-feature analytics      # Add analytics view
```
