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

# Archive
EXTRA_FLAGS=()
[ -n "${KEYCHAIN_PATH:-}" ] && EXTRA_FLAGS+=(OTHER_CODE_SIGN_FLAGS="--keychain ${KEYCHAIN_PATH}")

xcodebuild archive \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM=T7H24G7BFW \
  "${EXTRA_FLAGS[@]}"

# Export .app with Developer ID signing
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_DIR"

APP="$EXPORT_DIR/CleanKey.app"
if [ ! -d "$APP" ]; then
  echo "Error: exported app not found at $APP" >&2
  exit 1
fi

# Verify signing
echo "Verifying code signature..."
codesign --verify --deep --strict "$APP"
spctl --assess --type exec "$APP" 2>/dev/null || echo "Note: spctl assessment failed (normal without notarization)"

# Verify the TCC identity (designated requirement) is the stable Developer ID form.
# macOS keys the Accessibility grant to this requirement. If it is not the stable
# Developer ID + team form, the grant resets on every update (cdhash pinning) and
# users are re-prompted after each install. Fail the build before that can ship.
echo "Verifying TCC signing identity (designated requirement)..."
DR=$(codesign -d -r- "$APP" 2>&1 || true)
echo "$DR"

if ! printf '%s\n' "$DR" | grep -q 'identifier "it.stefer.CleanKey"'; then
  echo "Error: designated requirement is missing identifier \"it.stefer.CleanKey\"." >&2
  echo "The app is not signed with the stable Developer ID identity; the Accessibility" >&2
  echo "permission would reset on every update. Aborting." >&2
  exit 1
fi

if ! printf '%s\n' "$DR" | grep -q 'T7H24G7BFW'; then
  echo "Error: designated requirement is not anchored on team OU T7H24G7BFW." >&2
  echo "Signing is ad-hoc or uses a different identity; the grant would reset per update. Aborting." >&2
  exit 1
fi

# Hardened runtime must be active and the authority must be a Developer ID
# Application certificate (not ad-hoc / 'Apple Development') for the stable DR to hold.
SIGN_INFO=$(codesign -d --verbose=2 "$APP" 2>&1 || true)
if ! printf '%s\n' "$SIGN_INFO" | grep -q 'flags=.*runtime'; then
  echo "Error: hardened runtime flag is not set on the signed app." >&2
  echo "Without it the Developer ID identity is not honoured and the grant would reset. Aborting." >&2
  exit 1
fi

if ! printf '%s\n' "$SIGN_INFO" | grep -q 'Authority=Developer ID Application'; then
  echo "Error: app is not signed by a 'Developer ID Application' certificate" >&2
  echo "(authority shows ad-hoc or 'Apple Development'). The grant would reset per update. Aborting." >&2
  exit 1
fi

echo "TCC identity OK: stable Developer ID designated requirement, hardened runtime active."

# Create DMG with Applications alias for drag-to-install
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/CleanKey.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$DIST"
echo "Creating $DMG_NAME..."
hdiutil create \
  -volname "CleanKey" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING"

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
  echo "WARNING: APPLE_ID not set — skipping notarization." >&2
  echo "  The Accessibility grant still persists across updates (TCC keys on the stable" >&2
  echo "  Developer ID requirement verified above, not on notarization), but an un-notarized" >&2
  echo "  build hits Gatekeeper friction on first launch on macOS Sonoma+. Notarize for release." >&2
fi

echo ""
echo "Done: $DMG_PATH"
