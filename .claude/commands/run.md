# Build and Run

Build and launch Clocked-In on this Mac.

## Instructions

1. Use XcodeBuildMCP's macOS build-and-run tool:
   - `mcp__xcodebuildmcp__build_run_mac_proj` (project `clocked-in.xcodeproj`, scheme `clocked-in`)

   Fallback without XcodeBuildMCP:
   ```bash
   xcodebuild -project clocked-in.xcodeproj -scheme clocked-in -destination 'platform=macOS' -derivedDataPath build build
   open build/Build/Products/Debug/clocked-in.app
   ```

2. The app launches directly on macOS (it is not an iOS app; there is no simulator)

3. Watch for:
   - Console output for errors
   - Backend / WebSocket connection issues (Debug builds talk to `localhost:8000`)
   - Permission prompts

## Usage

```
/project:run             # Build and run on this Mac
```

## Notes

- The app runs as a notch / menu bar accessory app (no Dock icon)
- Hover over or click the notch area to expand the UI
- Check Console.app for detailed logs
