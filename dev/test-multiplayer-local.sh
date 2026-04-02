#!/usr/bin/env bash
#
# test-multiplayer-local.sh
# Launches two Godot instances side-by-side for local multiplayer testing.
# The user hosts/joins manually through the in-game Steam lobby UI.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WINDOW_W=960
WINDOW_H=540

# ---------------------------------------------------------------------------
# Find Godot binary
# ---------------------------------------------------------------------------
GODOT=""
if command -v godot &>/dev/null; then
    GODOT="godot"
elif [ -d "/Applications/Godot.app" ]; then
    GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
elif [ -d "$HOME/Applications/Godot.app" ]; then
    GODOT="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
else
    # Try any Godot variant in /Applications
    for app in /Applications/Godot*.app; do
        if [ -d "$app" ]; then
            GODOT="$app/Contents/MacOS/Godot"
            break
        fi
    done
fi

if [ -z "$GODOT" ]; then
    echo "ERROR: Could not find Godot. Install it or add it to PATH."
    exit 1
fi

echo "Using Godot: $GODOT"
echo ""

# ---------------------------------------------------------------------------
# Clean shutdown -- kill both instances on Ctrl-C
# ---------------------------------------------------------------------------
HOST_PID=""
CLIENT_PID=""

cleanup() {
    echo ""
    echo "Shutting down..."
    [ -n "$HOST_PID" ]   && kill "$HOST_PID"   2>/dev/null || true
    [ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" 2>/dev/null || true
    wait 2>/dev/null || true
    echo "Done."
}
trap cleanup SIGINT SIGTERM EXIT

# ---------------------------------------------------------------------------
# Launch Host (left half)
# ---------------------------------------------------------------------------
echo "Launching HOST instance (left half)..."
"$GODOT" \
    --path "$PROJECT_DIR" \
    --position 0,0 \
    --resolution "${WINDOW_W}x${WINDOW_H}" \
    &
HOST_PID=$!

# Small delay so Steam doesn't collide on init
sleep 2

# ---------------------------------------------------------------------------
# Launch Client (right half)
# ---------------------------------------------------------------------------
echo "Launching CLIENT instance (right half)..."
"$GODOT" \
    --path "$PROJECT_DIR" \
    --position ${WINDOW_W},0 \
    --resolution "${WINDOW_W}x${WINDOW_H}" \
    &
CLIENT_PID=$!

# ---------------------------------------------------------------------------
# Instructions
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "  Two Godot instances are now running."
echo ""
echo "  LEFT  window = Host"
echo "  RIGHT window = Client"
echo ""
echo "  1. In the LEFT window, create/host a lobby."
echo "  2. In the RIGHT window, join that lobby."
echo "  3. Press Ctrl-C here to close both."
echo "============================================"
echo ""

# Wait for either process to exit
wait
