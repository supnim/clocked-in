# Fix GitHub Issue

Investigate and fix a GitHub issue.

## Instructions

Given an issue number or description:

1. **Understand the Issue**
   - Read the issue description carefully
   - Identify which component is affected (Notch, Firebase, Activity, UI)
   - Reproduce if possible

2. **Locate Relevant Code**
   Use the key files reference:
   | Component | Files |
   |-----------|-------|
   | Notch UI | `Core/Notch/*.swift` |
   | Activity | `Core/Activity/*.swift` |
   | Presence | `Core/Presence/*.swift`, `Services/Firebase/RealtimeDBService.swift` |
   | Auth | `Services/Firebase/AuthService.swift` |
   | Friends | `Services/Firebase/FriendService.swift` |
   | UI Views | `UI/Views/*.swift` |

3. **Implement Fix**
   - Follow existing patterns (check CLAUDE.md)
   - Keep changes minimal and focused
   - Add comments only if logic is non-obvious

4. **Verify Fix**
   - Build: `/project:build`
   - Test: `/project:test`
   - Manual verification if needed

5. **Commit**
   - Use conventional commit format
   - Reference issue number: `fix: resolve #123`

## Usage
```
/project:fix-issue 42     # Fix issue #42
/project:fix-issue "notch not closing"  # Fix by description
```
