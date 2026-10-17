#!/usr/bin/env bash
#
# Package PiDesktop.app into a DMG, using only Apple's own tools
# (xcodebuild / codesign / diskutil / notarytool). No third-party dependency.
#
# This is the lower-level packager. For a production release (CI gate + identity
# verification), use scripts/release.sh, which calls this script.
#
# Default output is an ad-hoc signed, **un-notarized** DMG: it runs locally and
# can be shared for testing, but Gatekeeper blocks the first launch on another
# machine until the user explicitly allows it. See docs/workflows.md §6.
#
#   ./scripts/make-dmg.sh                       # ad-hoc, internal testing
#   ./scripts/make-dmg.sh --version 0.2.0
#   ./scripts/make-dmg.sh --output ./dist
#
# Distribution (needs an Apple Developer Program "Developer ID Application" cert):
#   ./scripts/make-dmg.sh \
#       --sign "Developer ID Application: Your Name (TEAMID)" \
#       --notarize --keychain-profile PiDesktop-notary
#
set -euo pipefail

cd "$(dirname "$0")/.."

readonly PROJECT="PiDesktop.xcodeproj"
readonly SCHEME="PiDesktop"
readonly APP_NAME="PiDesktop"
readonly VOLUME_NAME="PiDesktop"
readonly ARCHIVE_PATH=".build/${APP_NAME}.xcarchive"
readonly STAGING_DIR=".build/dmg-staging"

# --- Defaults ---------------------------------------------------------------
VERSION=""
OUTPUT_DIR=".build/dmg"
SIGN_IDENTITY=""
NOTARIZE=0
KEYCHAIN_PROFILE="${NOTARY_PROFILE:-}"

usage() {
    cat <<'EOF'
Package PiDesktop into a DMG.

Usage: ./scripts/make-dmg.sh [options]

Options:
  --version VERSION          Override the version in the DMG filename
                             (defaults to CFBundleShortVersionString).
  --output DIR               Where to write the DMG (default: .build/dmg).
  --sign IDENTITY            "Developer ID Application: ..." identity used to
                             sign the app and the DMG. Omit for ad-hoc signing.
  --notarize                 Submit the DMG to Apple and staple the ticket.
                             Requires --sign and a notarytool keychain profile.
  --keychain-profile NAME    notarytool profile to use (or NOTARY_PROFILE env).
  -h, --help                 Show this help.

Examples:
  ./scripts/make-dmg.sh
  ./scripts/make-dmg.sh --version 0.2.0 --output ./dist
  ./scripts/make-dmg.sh --sign "Developer ID Application: Name (TEAMID)" \
      --notarize --keychain-profile PiDesktop-notary
EOF
}

# --- Argument parsing -------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --output) OUTPUT_DIR="${2:?--output needs a value}"; shift 2 ;;
        --sign) SIGN_IDENTITY="${2:?--sign needs a value}"; shift 2 ;;
        --keychain-profile) KEYCHAIN_PROFILE="${2:?--keychain-profile needs a value}"; shift 2 ;;
        --notarize) NOTARIZE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$NOTARIZE" -eq 1 ]; then
    # Notarization only accepts Developer ID signed code; fail early, not after
    # a long archive.
    [ -n "$SIGN_IDENTITY" ] || { echo "--notarize requires --sign" >&2; exit 2; }
    [ -n "$KEYCHAIN_PROFILE" ] || { echo "--notarize requires --keychain-profile (or NOTARY_PROFILE)" >&2; exit 2; }
fi

# --- Toolchain --------------------------------------------------------------
# The macOS 27.0 deployment target needs the full Xcode SDK, not just
# CommandLineTools (same fallback as scripts/ci.sh).
if ! xcodebuild -version >/dev/null 2>&1; then
    for candidate in /Applications/Xcode.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer; do
        if [ -d "$candidate" ]; then
            export DEVELOPER_DIR="$candidate"
            break
        fi
    done
fi
echo "Toolchain: $(xcodebuild -version 2>&1 | head -1)"

# --- Archive ----------------------------------------------------------------
# Ad-hoc ("-") needs no certificate; a Developer ID identity is passed through
# so xcodebuild signs with the hardened runtime from ENABLE_HARDENED_RUNTIME.
rm -rf "$ARCHIVE_PATH"
echo "Archiving ${SCHEME} (Release)…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${SIGN_IDENTITY:--}" \
    archive

APP="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
[ -d "$APP" ] || { echo "Archive produced no app at $APP" >&2; exit 1; }

if [ -z "$VERSION" ]; then
    VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
fi

# A Developer ID signature must carry a secure timestamp for notarization;
# re-sign explicitly rather than trusting the archive's flags.
if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing app with \"$SIGN_IDENTITY\"…"
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

# --- Build the DMG ----------------------------------------------------------
# Create a compressed read-only (UDZO) DMG from a folder. macOS 26 deprecated
# `hdiutil create` in favour of `diskutil image create from`; prefer the new
# tool and keep hdiutil as a fallback for older build hosts.
create_dmg() {
    local source="$1" destination="$2"
    if diskutil image create from --help >/dev/null 2>&1; then
        diskutil image create from --format UDZO --volumeName "$VOLUME_NAME" \
            "$source" "$destination"
    else
        hdiutil create -volname "$VOLUME_NAME" -srcfolder "$source" \
            -ov -format UDZO "$destination"
    fi
}

# Staging holds the app plus an /Applications symlink so users can drag-install.
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$OUTPUT_DIR"
DMG_PATH="$OUTPUT_DIR/${APP_NAME}-${VERSION}.dmg"
echo "Creating ${DMG_PATH} …"
create_dmg "$STAGING_DIR" "$DMG_PATH"

if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

# --- Notarize ---------------------------------------------------------------
if [ "$NOTARIZE" -eq 1 ]; then
    echo "Submitting to Apple (this can take a few minutes)…"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" --wait
    # Staple so Gatekeeper can verify offline (no network round-trip on launch).
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

# --- Report -----------------------------------------------------------------
SIGNATURE="$(codesign -dv "$APP" 2>&1 | sed -n 's/^Signature=//p')"
echo
echo "Built $DMG_PATH"
echo "  app signature: ${SIGNATURE:-unknown}"
if [ "$NOTARIZE" -eq 1 ]; then
    echo "  notarized:     yes (stapled)"
elif [ -n "$SIGN_IDENTITY" ]; then
    echo "  notarized:     no — Gatekeeper will block first launch elsewhere"
else
    echo "  notarized:     no — ad-hoc; users must allow it on first launch"
    echo "  See docs/workflows.md §6 for the user-facing steps."
fi
