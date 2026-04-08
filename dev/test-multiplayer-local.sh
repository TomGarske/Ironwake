#!/usr/bin/env bash
#
# test-multiplayer-local.sh
# Launches up to 4 Godot instances in a grid for local multiplayer testing.
# The user hosts/joins manually through the in-game Steam lobby UI.
#
# Usage:
#   ./test-multiplayer-local.sh        # 2 players (default)
#   ./test-multiplayer-local.sh 3      # 3 players
#   ./test-multiplayer-local.sh 4      # 4 players

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAYER_COUNT="${1:-2}"

if [ "$PLAYER_COUNT" -lt 2 ] || [ "$PLAYER_COUNT" -gt 4 ]; then
    echo "Usage: $0 [2|3|4]"
    echo "  Launches 2-4 Godot instances for local multiplayer testing."
    exit 1
fi

# Window sizing: 2 players = side-by-side, 3-4 = 2x2 grid
if [ "$PLAYER_COUNT" -le 2 ]; then
    WINDOW_W=960
    WINDOW_H=540
else
    WINDOW_W=960
    WINDOW_H=540
fi

# Grid positions: [x,y] for each player slot
POSITIONS=("0,0" "${WINDOW_W},0" "0,${WINDOW_H}" "${WINDOW_W},${WINDOW_H}")
LABELS=("Host (top-left)" "Client 1 (top-right)" "Client 2 (bottom-left)" "Client 3 (bottom-right)")

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
echo "Launching $PLAYER_COUNT instances..."
echo ""

# ---------------------------------------------------------------------------
# Clean shutdown -- kill all instances on Ctrl-C
# ---------------------------------------------------------------------------
PIDS=()

cleanup() {
    echo ""
    echo "Shutting down..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    echo "Done."
}
trap cleanup SIGINT SIGTERM EXIT

# ---------------------------------------------------------------------------
# Launch instances
# ---------------------------------------------------------------------------
for i in $(seq 0 $((PLAYER_COUNT - 1))); do
    POS="${POSITIONS[$i]}"
    LABEL="${LABELS[$i]}"
    echo "Launching ${LABEL}..."
    "$GODOT" \
        --path "$PROJECT_DIR" \
        --position "${POS}" \
        --resolution "${WINDOW_W}x${WINDOW_H}" \
        &
    PIDS+=($!)
    # Stagger launches so Steam doesn't collide on init
    sleep 2
done

# ---------------------------------------------------------------------------
# Instructions
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "  $PLAYER_COUNT Godot instances are now running."
echo ""
for i in $(seq 0 $((PLAYER_COUNT - 1))); do
    echo "  ${LABELS[$i]}"
done
echo ""
echo "  1. In the HOST window, create/host a lobby."
echo "  2. In other windows, join that lobby."
echo "  3. Host selects game mode (Ironwake or Fleet Battle)."
echo "  4. Press Ctrl-C here to close all instances."
echo "============================================"
echo ""

# Wait for any process to exit
wait
