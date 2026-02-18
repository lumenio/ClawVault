#!/bin/bash
# e2e/run.sh — Build, install, and run ClawVault E2E tests against real Base + Pimlico.
#
# Usage:
#   ./e2e/run.sh --factory 0x... --recovery 0x...
#
# Prerequisites:
#   - macOS with Secure Enclave (Apple Silicon or T2)
#   - Foundry installed (cast)
#   - Node.js 20+
#   - Funded account on Base (~0.01 ETH + 5 USDC)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DAEMON_DIR="$PROJECT_DIR/daemon"
COMPANION_DIR="$PROJECT_DIR/companion"
PLIST_SRC="$SCRIPT_DIR/com.clawvault.daemon.test.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.clawvault.daemon.plist"
CLAWVAULT_DIR="$HOME/.clawvault"
BACKUP_DIR="$HOME/.clawvault-e2e-backup"
DAEMON_BINARY="$DAEMON_DIR/.build/debug/ClawVaultDaemon"
COMPANION_BINARY="$COMPANION_DIR/.build/debug/ClawVaultCompanion"
COMPANION_PID=""

# ── Parse args ──────────────────────────────────────────────────────────────────
FACTORY_ADDRESS=""
RECOVERY_ADDRESS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --factory)
            FACTORY_ADDRESS="$2"
            shift 2
            ;;
        --recovery)
            RECOVERY_ADDRESS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --factory 0x... --recovery 0x..."
            exit 1
            ;;
    esac
done

if [[ -z "$FACTORY_ADDRESS" ]]; then
    echo "ERROR: --factory is required"
    echo "Usage: $0 --factory 0x... --recovery 0x..."
    exit 1
fi

if [[ -z "$RECOVERY_ADDRESS" ]]; then
    echo "ERROR: --recovery is required"
    echo "Usage: $0 --factory 0x... --recovery 0x..."
    exit 1
fi

# ── Cleanup function ────────────────────────────────────────────────────────────
cleanup() {
    echo ""
    echo "==> Tearing down..."
    "$SCRIPT_DIR/teardown.sh" || true
}
trap cleanup EXIT

# ── Step 1: Back up existing config ─────────────────────────────────────────────
if [[ -d "$CLAWVAULT_DIR" ]]; then
    echo "==> Backing up existing ~/.clawvault/ to $BACKUP_DIR"
    rm -rf "$BACKUP_DIR"
    cp -a "$CLAWVAULT_DIR" "$BACKUP_DIR"
fi

# ── Step 2: Build daemon ────────────────────────────────────────────────────────
echo "==> Building daemon..."
cd "$DAEMON_DIR" && swift build 2>&1 | tail -5
echo "    ok"

# ── Step 3: Codesign daemon ────────────────────────────────────────────────────
echo "==> Codesigning daemon..."
"$PROJECT_DIR/scripts/codesign-dev.sh" 2>&1 | tail -2
echo "    ok"

# ── Step 4: Build companion ────────────────────────────────────────────────────
echo "==> Building companion..."
cd "$COMPANION_DIR" && swift build 2>&1 | tail -5
echo "    ok"

# ── Step 5: Unload existing daemon if running ──────────────────────────────────
if launchctl list com.clawvault.daemon &>/dev/null; then
    echo "==> Unloading existing daemon..."
    launchctl unload "$PLIST_DST" 2>/dev/null || true
    sleep 1
fi

# ── Step 6: Install test plist ──────────────────────────────────────────────────
echo "==> Installing launchd service..."
# Patch plist with actual binary path
sed "s|__DAEMON_BINARY__|$DAEMON_BINARY|g" "$PLIST_SRC" > "$PLIST_DST"
launchctl load "$PLIST_DST"
echo "    ok"

# ── Step 7: Create dev-mode flag ───────────────────────────────────────────────
mkdir -p "$CLAWVAULT_DIR"
chmod 700 "$CLAWVAULT_DIR"
touch "$CLAWVAULT_DIR/dev-mode"

# ── Step 8: Wait for daemon /health ────────────────────────────────────────────
echo -n "==> Waiting for daemon..."
SOCKET="$CLAWVAULT_DIR/daemon.sock"
MAX_WAIT=30
WAITED=0
while [[ $WAITED -lt $MAX_WAIT ]]; do
    if [[ -S "$SOCKET" ]]; then
        HEALTH=$(curl -s --unix-socket "$SOCKET" http://localhost/health 2>/dev/null || true)
        if echo "$HEALTH" | grep -q '"status"'; then
            echo " ok"
            break
        fi
    fi
    sleep 1
    WAITED=$((WAITED + 1))
    echo -n "."
done

if [[ $WAITED -ge $MAX_WAIT ]]; then
    echo " TIMEOUT"
    echo "Daemon failed to start. Check /tmp/clawvault-e2e-daemon.log"
    cat /tmp/clawvault-e2e-daemon.log 2>/dev/null | tail -20
    exit 1
fi

# ── Step 9: Start companion in background ──────────────────────────────────────
echo "==> Starting companion..."
"$COMPANION_BINARY" &>/tmp/clawvault-e2e-companion.log &
COMPANION_PID=$!
echo "    ok (PID: $COMPANION_PID)"

# ── Step 10: Wait for XPC connection ───────────────────────────────────────────
echo -n "==> Waiting for XPC connection..."
XPC_WAIT=15
XPC_WAITED=0
while [[ $XPC_WAITED -lt $XPC_WAIT ]]; do
    CAPS=$(curl -s --unix-socket "$SOCKET" http://localhost/capabilities 2>/dev/null || true)
    if echo "$CAPS" | grep -q '"profile"'; then
        echo " ok"
        break
    fi
    sleep 1
    XPC_WAITED=$((XPC_WAITED + 1))
    echo -n "."
done

if [[ $XPC_WAITED -ge $XPC_WAIT ]]; then
    echo " TIMEOUT (companion may not be connected, admin approval tests may fail)"
fi

# ── Step 11: Run E2E tests ─────────────────────────────────────────────────────
echo "==> Running E2E tests..."
echo ""

export CLAWVAULT_SOCKET="$SOCKET"
export CLAWVAULT_FACTORY="$FACTORY_ADDRESS"
export CLAWVAULT_RECOVERY="$RECOVERY_ADDRESS"
export CLAWVAULT_CHAIN_ID="8453"
export CLAWVAULT_SKILL_DIR="$PROJECT_DIR/skill"

cd "$SCRIPT_DIR"
node --test tests/

echo ""
echo "==> All tests complete!"
