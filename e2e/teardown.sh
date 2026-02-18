#!/bin/bash
# e2e/teardown.sh — Unload test daemon, stop companion, restore backup.
# Safe to run multiple times.

set -uo pipefail

PLIST_DST="$HOME/Library/LaunchAgents/com.clawvault.daemon.plist"
CLAWVAULT_DIR="$HOME/.clawvault"
BACKUP_DIR="$HOME/.clawvault-e2e-backup"

# Unload launchd service
if launchctl list com.clawvault.daemon &>/dev/null; then
    echo "  Unloading daemon..."
    launchctl unload "$PLIST_DST" 2>/dev/null || true
fi
rm -f "$PLIST_DST"

# Kill companion if running
COMPANION_PIDS=$(pgrep -f ClawVaultCompanion 2>/dev/null || true)
if [[ -n "$COMPANION_PIDS" ]]; then
    echo "  Stopping companion (PIDs: $COMPANION_PIDS)..."
    kill $COMPANION_PIDS 2>/dev/null || true
fi

# Remove stale socket
rm -f "$CLAWVAULT_DIR/daemon.sock"

# Restore backup if present
if [[ -d "$BACKUP_DIR" ]]; then
    echo "  Restoring ~/.clawvault/ from backup..."
    rm -rf "$CLAWVAULT_DIR"
    mv "$BACKUP_DIR" "$CLAWVAULT_DIR"
fi

echo "  Teardown complete."
