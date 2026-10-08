# Build Project

Build the Clocked-In macOS app (this is a native macOS app — there is no simulator target).

## Instructions

1. Prefer XcodeBuildMCP's macOS tools:
   - `mcp__xcodebuildmcp__build_mac_proj` (project `clocked-in.xcodeproj`, scheme `clocked-in`)

   If XcodeBuildMCP is unavailable, fall back to:
   ```bash
   xcodebuild -project clocked-in.xcodeproj -scheme clocked-in -destination 'platform=macOS' build
   ```

2. Check for build errors and fix them before proceeding

3. If build fails:
   - Read the error messages carefully
   - Common issues: missing imports, type mismatches, async/await and actor-isolation errors
   - Fix issues and rebuild

## Usage

```
/project:build           # Debug build for macOS
/project:build release   # Release configuration
```
