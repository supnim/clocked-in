# Clean Build

Clean the Xcode build folder to resolve stale build issues.

## Instructions

1. Use XcodeBuildMCP clean tools or run:
   ```bash
   xcodebuild clean -scheme clocked-in
   ```

2. Also consider cleaning derived data:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/clocked-in-*
   ```

## When to Use

- Build errors that don't make sense
- After changing Swift package dependencies
- After Xcode updates
- "Module not found" errors
- Stale cache issues

## Usage

```
/project:clean           # Clean build folder
```
