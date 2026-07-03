# Run Tests

Run the test suite for Clocked-In.

## Instructions

1. Use XcodeBuildMCP test tools:
   - `mcp__xcodebuildmcp__test_sim_name_proj`

2. Analyze test results:
   - Report which tests passed/failed
   - For failures, show the assertion that failed
   - Suggest fixes for failing tests

3. If tests fail:
   - Read the test file to understand the expected behavior
   - Check if it's a test bug or implementation bug
   - Fix accordingly

## Usage

```
/project:test            # Run all tests
/project:test Unit       # Run unit tests only
/project:test UI         # Run UI tests only
```
