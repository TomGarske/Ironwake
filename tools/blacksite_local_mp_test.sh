#!/usr/bin/env bash
set -euo pipefail

# Blacksite local multiplayer test harness.
# Runs host/client on localhost without a second Steam account.
#
# Modes:
#   visual (default): launches 2 interactive windows
#   smoke:            runs headless host/client autotest and prints PASS/FAIL
#
# Examples:
#   ./tools/blacksite_local_mp_test.sh
#   ./tools/blacksite_local_mp_test.sh --mode visual --port 29777
#   ./tools/blacksite_local_mp_test.sh --mode smoke --godot /opt/homebrew/bin/godot

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="visual"
PORT="29777"
HOST="127.0.0.1"
GODOT_BIN="${GODOT_BIN:-}"
RESOLUTION="1280x720"
HOST_POSITION="40,80"
CLIENT_POSITION="1360,80"

SCENE_PATH="res://scenes/game/blacksite/blacksite_containment_arena.tscn"

contains_success_line() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q "${pattern}" "${file}"
    return $?
  fi
  grep -qE "${pattern}" "${file}"
}

usage() {
  cat <<'EOF'
Usage: ./tools/blacksite_local_mp_test.sh [options]

Options:
  --mode <visual|smoke>      Test mode (default: visual)
  --port <port>              Local ENet port (default: 29777)
  --host <ip>                Local ENet host (default: 127.0.0.1)
  --godot <path>             Path to Godot binary (auto-detected if omitted)
  --resolution <WxH>         Visual window resolution (default: 1280x720)
  --host-position <X,Y>      Host window position (default: 40,80)
  --client-position <X,Y>    Client window position (default: 1360,80)
  -h, --help                 Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --godot)
      GODOT_BIN="${2:-}"
      shift 2
      ;;
    --resolution)
      RESOLUTION="${2:-}"
      shift 2
      ;;
    --host-position)
      HOST_POSITION="${2:-}"
      shift 2
      ;;
    --client-position)
      CLIENT_POSITION="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${GODOT_BIN}" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  elif command -v godot4 >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot4)"
  elif [[ -x "/opt/homebrew/bin/godot" ]]; then
    GODOT_BIN="/opt/homebrew/bin/godot"
  else
    echo "Could not find Godot binary. Use --godot /path/to/godot." >&2
    exit 1
  fi
fi

if [[ ! -x "${GODOT_BIN}" ]]; then
  echo "Godot binary is not executable: ${GODOT_BIN}" >&2
  exit 1
fi

if [[ ! -f "${PROJECT_ROOT}/project.godot" ]]; then
  echo "project.godot not found at ${PROJECT_ROOT}" >&2
  exit 1
fi

echo "Using Godot: ${GODOT_BIN}"
echo "Project root: ${PROJECT_ROOT}"
echo "Mode: ${MODE}"
echo "Host: ${HOST}:${PORT}"

HOST_CMD=(
  "${GODOT_BIN}"
  --path "${PROJECT_ROOT}"
  --scene "${SCENE_PATH}"
)

CLIENT_CMD=(
  "${GODOT_BIN}"
  --path "${PROJECT_ROOT}"
  --scene "${SCENE_PATH}"
)

if [[ "${MODE}" == "visual" ]]; then
  HOST_CMD+=(--position "${HOST_POSITION}" --resolution "${RESOLUTION}" -- --local-mp=host --local-mp-port="${PORT}")
  CLIENT_CMD+=(--position "${CLIENT_POSITION}" --resolution "${RESOLUTION}" -- --local-mp=client --local-mp-host="${HOST}" --local-mp-port="${PORT}")

  echo "Launching host window..."
  "${HOST_CMD[@]}" >/dev/null 2>&1 &
  HOST_PID=$!
  sleep 1
  echo "Launching client window..."
  "${CLIENT_CMD[@]}" >/dev/null 2>&1 &
  CLIENT_PID=$!

  echo "Host PID: ${HOST_PID}"
  echo "Client PID: ${CLIENT_PID}"
  echo "Visual test running. Close both game windows when done."

  wait "${HOST_PID}" "${CLIENT_PID}" || true
  exit 0
fi

if [[ "${MODE}" == "smoke" ]]; then
  TMP_DIR="$(mktemp -d)"
  HOST_LOG="${TMP_DIR}/host.log"
  CLIENT_LOG="${TMP_DIR}/client.log"

  cleanup() {
    if [[ -n "${HOST_PID:-}" ]] && kill -0 "${HOST_PID}" >/dev/null 2>&1; then
      kill "${HOST_PID}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${CLIENT_PID:-}" ]] && kill -0 "${CLIENT_PID}" >/dev/null 2>&1; then
      kill "${CLIENT_PID}" >/dev/null 2>&1 || true
    fi
    rm -rf "${TMP_DIR}"
  }
  trap cleanup EXIT

  HOST_CMD+=(--headless -- --local-mp=host --local-mp-port="${PORT}" --local-mp-autotest --local-mp-autotest-quit)
  CLIENT_CMD+=(--headless -- --local-mp=client --local-mp-host="${HOST}" --local-mp-port="${PORT}" --local-mp-autotest --local-mp-autotest-quit)

  echo "Running headless host..."
  "${HOST_CMD[@]}" >"${HOST_LOG}" 2>&1 &
  HOST_PID=$!
  sleep 1
  echo "Running headless client..."
  "${CLIENT_CMD[@]}" >"${CLIENT_LOG}" 2>&1 || true

  wait "${HOST_PID}" || true

  HOST_OK=0
  CLIENT_OK=0
  if contains_success_line "\\[LocalMP-Test\\] Host roster size=2 success=true" "${HOST_LOG}"; then
    HOST_OK=1
  fi
  if contains_success_line "\\[LocalMP-Test\\] Client roster size=2 success=true" "${CLIENT_LOG}"; then
    CLIENT_OK=1
  fi

  echo "----- Host Log -----"
  sed -n '1,200p' "${HOST_LOG}"
  echo "----- Client Log -----"
  sed -n '1,200p' "${CLIENT_LOG}"

  if [[ "${HOST_OK}" -eq 1 && "${CLIENT_OK}" -eq 1 ]]; then
    echo "PASS: Local MP smoke test succeeded."
    exit 0
  fi

  echo "FAIL: Local MP smoke test did not meet expected success criteria." >&2
  exit 1
fi

echo "Invalid mode '${MODE}'. Use --mode visual or --mode smoke." >&2
exit 1
