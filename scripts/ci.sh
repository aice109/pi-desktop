#!/usr/bin/env bash
#
# Build and test PiDesktop with a working Xcode toolchain.
#
# The macOS 27.0 deployment target needs the full Xcode SDK, not just
# CommandLineTools. If `xcodebuild` reports "requires Xcode", this script points
# DEVELOPER_DIR at Xcode.app without requiring a sudo `xcode-select`.
#
# Used by CI (see .github/workflows/) and handy locally:
#   ./scripts/ci.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if ! xcodebuild -version >/dev/null 2>&1; then
    for candidate in /Applications/Xcode.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer; do
        if [ -d "$candidate" ]; then
            export DEVELOPER_DIR="$candidate"
            break
        fi
    done
fi

echo "Toolchain: $(xcodebuild -version 2>&1 | head -1)"

xcodebuild \
    -project PiDesktop.xcodeproj \
    -scheme PiDesktop \
    -configuration Debug \
    -destination 'platform=macOS' \
    build

xcodebuild \
    -project PiDesktop.xcodeproj \
    -scheme PiDesktop \
    -destination 'platform=macOS' \
    test
