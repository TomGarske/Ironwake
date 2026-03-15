#!/usr/bin/env bash
set -euo pipefail

# BurnBridgers — SteamOS / Linux GodotSteam setup
# Downloads and installs the GodotSteam GDExtension plugin.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/addons/addons.cfg"

if [[ ! -f "$CONFIG" ]]; then
    echo "ERROR: addons/addons.cfg not found at $CONFIG"
    exit 1
fi

source "$CONFIG"

# Warn if Godot is running (locked files will cause errors on reinstall)
if pgrep -xi "godot" &>/dev/null; then
    echo "WARNING: Godot appears to be running. Please close it before continuing."
    read -rp "Continue anyway? (y/N): " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "Aborted."
        exit 1
    fi
fi

DOWNLOAD_URL="${GODOTSTEAM_BASE_URL}/${GODOTSTEAM_GDE_TAG}/${GODOTSTEAM_ARCHIVE}"
ADDON_DIR="$SCRIPT_DIR/addons/godotsteam"

# Ensure required tools are available
for cmd in curl tar xz; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is required but not found. Install it and try again."
        exit 1
    fi
done

if [[ -d "$ADDON_DIR" ]]; then
    echo "GodotSteam already installed at $ADDON_DIR"
    read -rp "Reinstall? (y/N): " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "Skipped."
        exit 0
    fi
    rm -rf "$ADDON_DIR"
fi

echo "Downloading GodotSteam GDExtension v${GODOTSTEAM_VERSION}..."
TMPFILE=$(mktemp /tmp/godotsteam-XXXXXX.tar.xz)
trap 'rm -f "$TMPFILE"' EXIT

curl -fSL --progress-bar -o "$TMPFILE" "$DOWNLOAD_URL"

echo "Extracting to addons/godotsteam/..."
tar -xJf "$TMPFILE" -C "$SCRIPT_DIR"

# Create steam_appid.txt if it doesn't exist
STEAM_APPID_FILE="$SCRIPT_DIR/steam_appid.txt"
if [[ ! -f "$STEAM_APPID_FILE" ]]; then
    echo "$STEAM_APP_ID" > "$STEAM_APPID_FILE"
    echo "Created steam_appid.txt (app ID: $STEAM_APP_ID)"
fi

echo ""
echo "GodotSteam v${GODOTSTEAM_VERSION} installed successfully."
echo "Open the project in Godot to verify."
