#!/usr/bin/env bash
# Build and package Clocked In for distribution.
#
# Modes:
#   appstore  Archive (Release, automatic signing) and export for the Mac App Store
#             using ExportOptions-AppStore.plist. Set APPSTORE_UPLOAD=1 to upload
#             straight to App Store Connect instead of writing a .pkg.
#             Prereqs: Xcode signed in to the team (67QQB49ZUJ) with an
#             "Apple Distribution" / "Mac Installer Distribution" capable account.
#   dmg       Developer ID-signed, notarized DMG for direct download.
#             Prereqs: "Developer ID Application" certificate + private key in the
#             login keychain; APP_STORE_API_KEY / APP_STORE_API_ISSUER env vars set,
#             with the AuthKey .p8 at ~/.appstoreconnect/private_keys/AuthKey_$APP_STORE_API_KEY.p8
#
# Usage: scripts/release.sh [appstore|dmg] [output-dir]   (default mode: dmg, dir: ./dist)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

MODE="dmg"
case "${1:-}" in
  appstore|dmg) MODE="$1"; shift ;;
  -h|--help)
    sed -n '2,18p' "$0"; exit 0 ;;
esac

OUT_DIR="${1:-$PROJECT_DIR/dist}"
BUILD_DIR="$OUT_DIR/build"
APP_NAME="clocked-in"

# ---------------------------------------------------------------------------
# Mac App Store
# ---------------------------------------------------------------------------
if [ "$MODE" = "appstore" ]; then
  EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions-AppStore.plist"
  ARCHIVE_PATH="$BUILD_DIR/$APP_NAME-appstore.xcarchive"
  EXPORT_DIR="$OUT_DIR/appstore"
  [ -f "$EXPORT_OPTIONS" ] || { echo "Missing $EXPORT_OPTIONS" >&2; exit 1; }

  mkdir -p "$OUT_DIR" "$BUILD_DIR"
  rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

  echo "==> Archiving (Release, automatic signing, team 67QQB49ZUJ)"
  xcodebuild -project "$PROJECT_DIR/clocked-in.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=67QQB49ZUJ \
    -quiet

  OPTIONS_FILE="$EXPORT_OPTIONS"
  if [ "${APPSTORE_UPLOAD:-0}" = "1" ]; then
    OPTIONS_FILE="$BUILD_DIR/ExportOptions-upload.plist"
    cp "$EXPORT_OPTIONS" "$OPTIONS_FILE"
    /usr/libexec/PlistBuddy -c "Set :destination upload" "$OPTIONS_FILE"
    echo "==> Exporting and uploading to App Store Connect"
  else
    echo "==> Exporting App Store package"
  fi

  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$OPTIONS_FILE" \
    -allowProvisioningUpdates

  if [ "${APPSTORE_UPLOAD:-0}" = "1" ]; then
    echo "Done: uploaded. The build appears in App Store Connect > TestFlight after processing."
  else
    PKG_PATH="$(ls "$EXPORT_DIR"/*.pkg 2>/dev/null | head -n 1 || true)"
    echo "Done: ${PKG_PATH:-$EXPORT_DIR}"
    cat <<EOT

Upload the build to App Store Connect with one of:
  * Xcode > Window > Organizer > Archives > select "$ARCHIVE_PATH" > Distribute App
  * Transporter.app: drag in ${PKG_PATH:-the .pkg in $EXPORT_DIR} and click Deliver
  * xcrun altool --upload-app --type macos --file "${PKG_PATH:-$EXPORT_DIR/<app>.pkg}" \\
        --apiKey "\$APP_STORE_API_KEY" --apiIssuer "\$APP_STORE_API_ISSUER"
  * or re-run with APPSTORE_UPLOAD=1 scripts/release.sh appstore
EOT
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Developer ID DMG (direct download)
# ---------------------------------------------------------------------------
IDENTITY="Developer ID Application"
: "${APP_STORE_API_KEY:?Set APP_STORE_API_KEY for notarization}"
: "${APP_STORE_API_ISSUER:?Set APP_STORE_API_ISSUER for notarization}"
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
