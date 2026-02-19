#!/bin/bash
# codesign-dev.sh — Ad-hoc sign the daemon binary after swift build.
# Prevents SIGKILL on Secure Enclave access during development.
#
# Usage:
#   cd daemon && swift build && ../scripts/codesign-dev.sh
#
# NOTE: This does NOT create ~/.monolith/dev-mode.
# To enable relaxed XPC validation in debug builds, manually run:
#   touch ~/.monolith/dev-mode
# This prevents accidental weakening of security.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON_DIR="$SCRIPT_DIR/../daemon"
ENTITLEMENTS="$DAEMON_DIR/MonolithDaemon.entitlements"

# Find the built binary
BINARY="$DAEMON_DIR/.build/debug/MonolithDaemon"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    echo "Run 'cd daemon && swift build' first."
    exit 1
fi

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "ERROR: Entitlements file not found at $ENTITLEMENTS"
    exit 1
fi

echo "Signing $BINARY with entitlements..."
codesign --force -s - --entitlements "$ENTITLEMENTS" "$BINARY"
echo "Done. Binary is ad-hoc signed with Secure Enclave entitlements."
echo ""
echo "To enable relaxed XPC validation (debug builds only):"
echo "  touch ~/.monolith/dev-mode"
