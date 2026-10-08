#!/bin/bash
# Pre-build hook: Run SwiftLint if available

if command -v swiftlint &> /dev/null; then
    echo "Running SwiftLint..."
    swiftlint lint --quiet --config .swiftlint.yml 2>/dev/null || true
fi

# Check for common issues
echo "Checking for debug prints..."
grep -r "print(" clocked-in/ --include="*.swift" | grep -v "// DEBUG" | head -5

exit 0
