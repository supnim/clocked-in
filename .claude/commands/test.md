# Run Tests

Run the test suite for Clocked-In.

## Instructions

1. Client (XCTest, macOS): use XcodeBuildMCP's macOS test tool:
   - `mcp__xcodebuildmcp__test_macos_proj` (project `clocked-in.xcodeproj`, scheme `clocked-in`)

   Fallback without XcodeBuildMCP:
   ```bash
   xcodebuild -project clocked-in.xcodeproj -scheme clocked-in -destination 'platform=macOS' test
   ```

2. Backend (pytest): `cd backend && pytest`

3. Analyze test results:
   - Report which tests passed/failed
   - For failures, show the assertion that failed
   - Suggest fixes for failing tests

4. If tests fail:
   - Read the test file to understand the expected behavior
   - Check if it's a test bug or implementation bug
   - Fix accordingly

## Usage

```
/project:test            # Run all tests
/project:test client     # XCTest only
/project:test backend    # pytest only
```
