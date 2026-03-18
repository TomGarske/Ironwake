#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/blacksite_local_mp_test.sh" \
  --scene "res://scenes/game/strategy/strategy_game.tscn" \
  --host-success "\\[LocalMP\\] Host server listening on port" \
  --client-success "\\[LocalMP-Test\\] Client connected success=true" \
  "$@"
