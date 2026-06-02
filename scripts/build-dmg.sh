#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCHEME="CleanKey"
CONFIGURATION="Release"
PLIST="$ROOT/CleanKey/Info.plist"
EXPORT_OPTIONS="$ROOT/ExportOptions.plist"
ARCHIVE="/tmp/CleanKey.xcarchive"
EXPORT_DIR="/tmp/CleanKey-export"
DIST="$ROOT/dist"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
DMG_NAME="CleanKey-${VERSION}.dmg"
DMG_PATH="$DIST/$DMG_NAME"

echo "Building CleanKey ${VERSION}..."

# Show available signing identities (diagnostic)
echo "Available signing identities:"
security find-identity -v -p codesigning || true

# Archive
EXTRA_FLAGS=()
[ -n "${KEYCHAIN_PATH:-}" ] && EXTRA_FLAGS+=(OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH")

if command -v xcpretty &>/dev/null; then
  xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=T7H24G7BFW \
    "${EXTRA_FLAGS[@]}" \
    | xcpretty
else
  xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=T7H24G7BFW \
    "${EXTRA_FLAGS[@]}"
fi

# Export .app with Developer ID signing
if command -v xcpretty &>/dev/null; then
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_DIR" \
    | xcpretty
else
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_DIR"
fi

APP="$EXPORT_DIR/CleanKey.app"
if [ ! -d "$APP" ]; then
  echo "Error: exported app not found at $APP" >&2
  exit 1
fi

# Verify signing
echo "Verifying code signature..."
codesign --verify --deep --strict "$APP"
spctl --assess --type exec "$APP" 2>/dev/null || echo "Note: spctl assessment failed (normal without notarization)"

# Create DMG
mkdir -p "$DIST"
echo "Creating $DMG_NAME..."
hdiutil create \
  -volname "CleanKey" \
  -srcfolder "$APP" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# Notarize (optional — skipped when APPLE_ID is not set)
if [ -n "${APPLE_ID:-}" ]; then
  echo "Notarizing..."
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id T7H24G7BFW \
    --password "${NOTARYTOOL_PASSWORD:?NOTARYTOOL_PASSWORD required for notarization}" \
    --wait
  echo "Stapling notarization ticket..."
  xcrun stapler staple "$DMG_PATH"
  echo "Notarization complete."
else
  echo "APPLE_ID not set — skipping notarization."
fi

echo ""
echo "Done: $DMG_PATH"
