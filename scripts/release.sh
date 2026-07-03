#!/usr/bin/env bash
# Build, sign, notarize, and package Clocked In as a distributable DMG.
#
# Prereqs:
#   - "Developer ID Application" certificate + private key in the login keychain
#   - APP_STORE_API_KEY / APP_STORE_API_ISSUER env vars set, with the AuthKey .p8
#     at ~/.appstoreconnect/private_keys/AuthKey_$APP_STORE_API_KEY.p8
#
# Usage: scripts/release.sh [output-dir]   (default: ./dist)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$PROJECT_DIR/dist}"
BUILD_DIR="$OUT_DIR/build"
APP_NAME="clocked-in"
IDENTITY="Developer ID Application"
KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_${APP_STORE_API_KEY}.p8"

mkdir -p "$OUT_DIR" "$BUILD_DIR"

echo "==> Archiving (Release, Developer ID, Hardened Runtime)"
xcodebuild -project "$PROJECT_DIR/clocked-in.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  archive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  -quiet

APP_PATH="$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "Archive missing app bundle" >&2; exit 1; }

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Building DMG"
DMG_PATH="$OUT_DIR/ClockedIn.dmg"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Clocked In" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" -quiet

echo "==> Signing DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG_PATH"

echo "==> Notarizing (waits for Apple)"
xcrun notarytool submit "$DMG_PATH" \
  --key "$KEY_FILE" \
  --key-id "$APP_STORE_API_KEY" \
  --issuer "$APP_STORE_API_ISSUER" \
  --wait

echo "==> Stapling ticket"
xcrun stapler staple "$DMG_PATH"

echo "==> Gatekeeper assessment"
spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"

echo "Done: $DMG_PATH"
