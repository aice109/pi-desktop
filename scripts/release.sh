#!/usr/bin/env bash
#
# Build and package a production release of PiDesktop.
#
# This is the one-command release entry point. It runs the same gates as CI,
# delegates the actual Release build + DMG assembly to scripts/make-dmg.sh, and
# then verifies that the packaged app really is the production identity (not the
# DEBUG / 测试版 configuration).
#
#   ./scripts/release.sh
#   ./scripts/release.sh --output dist
#   ./scripts/release.sh --skip-checks
#   ./scripts/release.sh \
#       --sign "Developer ID Application: Your Name (TEAMID)" \
#       --notarize --keychain-profile PiDesktop-notary
#
# Output: <output>/PiDesktop-<version>.dmg (default: dist/)
#
# The version comes from the project's MARKETING_VERSION / CURRENT_PROJECT_VERSION.
# Bump those in Xcode before releasing; this script deliberately does not edit
# project settings.

set -euo pipefail

cd "$(dirname "$0")/.."

readonly PRODUCTION_BUNDLE_ID="io.github.aice109.PiDesktop"
readonly PRODUCTION_DISPLAY_NAME="Pi Desktop"
readonly ARCHIVE_APP=".build/PiDesktop.xcarchive/Products/Applications/PiDesktop.app"

OUTPUT_DIR="dist"
SKIP_CHECKS=0
PASSTHROUGH=()

usage() {
    cat <<'EOF'
Build and package a production release of PiDesktop.

Usage: ./scripts/release.sh [options]

Options:
  --output DIR               Where to write the DMG (default: dist).
  --skip-checks              Skip the format/build/test gate. Only for a quick
                             local package after the same commit already passed
                             CI; the production identity check still runs.
  --sign IDENTITY            "Developer ID Application: ..." identity used to
                             sign the app and the DMG. Omit for ad-hoc signing.
  --notarize                 Submit the DMG to Apple and staple the ticket.
                             Requires --sign and a notarytool keychain profile.
  --keychain-profile NAME    notarytool profile to use (or NOTARY_PROFILE env).
  -h, --help                 Show this help.

Output:
  <output>/PiDesktop-<version>.dmg
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --output) OUTPUT_DIR="${2:?--output needs a value}"; shift 2 ;;
        --skip-checks) SKIP_CHECKS=1; shift ;;
        --sign|--keychain-profile) PASSTHROUGH+=("$1" "${2:?$1 needs a value}"); shift 2 ;;
        --notarize) PASSTHROUGH+=("$1"); shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

echo "==> 1/4 Pre-release checks"
if [ "$SKIP_CHECKS" -eq 1 ]; then
    echo "    skipped (--skip-checks)"
else
    # scripts/ci.sh runs format.sh first, then Debug build + tests. A green
    # Debug gate does not prove Release compiles, so the Release build below is
    # still mandatory.
    ./scripts/ci.sh
fi

echo "==> 2/4 Build Release and create the DMG"
# Bash 3.2 (macOS default) treats an empty "${array[@]}" as unbound under set -u.
./scripts/make-dmg.sh --output "$OUTPUT_DIR" ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}

echo "==> 3/4 Verify the production identity"
if [ ! -d "$ARCHIVE_APP" ]; then
    echo "✗ Missing archive app: $ARCHIVE_APP" >&2
    exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$ARCHIVE_APP/Contents/Info.plist")"
DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$ARCHIVE_APP/Contents/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ARCHIVE_APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ARCHIVE_APP/Contents/Info.plist")"

if [ "$BUNDLE_ID" != "$PRODUCTION_BUNDLE_ID" ]; then
    echo "✗ Refusing to release bundle id '$BUNDLE_ID' (expected '$PRODUCTION_BUNDLE_ID')" >&2
    exit 1
fi
if [ "$DISPLAY_NAME" != "$PRODUCTION_DISPLAY_NAME" ]; then
    echo "✗ Refusing to release display name '$DISPLAY_NAME' (expected '$PRODUCTION_DISPLAY_NAME')" >&2
    exit 1
fi
codesign --verify --strict "$ARCHIVE_APP"

DMG_PATH="$OUTPUT_DIR/PiDesktop-$VERSION.dmg"
if [ ! -f "$DMG_PATH" ]; then
    echo "✗ Expected DMG missing: $DMG_PATH" >&2
    exit 1
fi

echo "==> 4/4 Done"
SIGNATURE="$(codesign -dv "$ARCHIVE_APP" 2>&1 | sed -n 's/^Signature=//p')"
echo "  file:      $DMG_PATH"
echo "  app:       $DISPLAY_NAME ($BUNDLE_ID)"
echo "  version:   $VERSION ($BUILD)"
echo "  signature: ${SIGNATURE:-unknown}"
echo "  size:      $(du -h "$DMG_PATH" | cut -f1)"
