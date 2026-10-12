#!/usr/bin/env bash
#
# Lint or format Swift sources with the swift-format bundled in Xcode.
# No third-party dependency.
#
#   ./scripts/format.sh          # check (lint; non-zero on any finding)
#   ./scripts/format.sh --fix    # format in place
set -euo pipefail

cd "$(dirname "$0")/.."

if ! xcrun --find swift-format >/dev/null 2>&1; then
    echo "swift-format not found. It ships with the Xcode toolchain; install Xcode." >&2
    exit 1
fi

if [ "${1:-}" = "--fix" ]; then
    xcrun swift-format format --configuration .swift-format --in-place --recursive PiDesktop PiDesktopTests
    echo "Formatted PiDesktop and PiDesktopTests."
else
    xcrun swift-format lint --configuration .swift-format --strict --recursive PiDesktop PiDesktopTests
    echo "Lint clean."
fi
