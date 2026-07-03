# Build Project

Build the Clocked-In macOS app for the simulator or device.

## Instructions

1. Use XcodeBuildMCP tools (NOT raw xcodebuild):
   - For simulator: `mcp__xcodebuildmcp__build_sim_name_proj`
   - For device: `mcp__xcodebuildmcp__build_device_proj`

2. Check for build errors and fix them before proceeding

3. If build fails:
   - Read the error messages carefully
   - Common issues: missing imports, type mismatches, async/await errors
   - Fix issues and rebuild

## Usage

```
/project:build           # Build for simulator (default)
/project:build device    # Build for connected device
```
