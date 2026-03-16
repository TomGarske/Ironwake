#!/usr/bin/env bash
set -euo pipefail

# BurnBridgers — SteamOS / Linux addon setup
# Downloads and installs GDExtension plugins (GodotSteam, LimboAI).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Addon versions ────────────────────────────────────────────────────
# GodotSteam GDExtension plugin
GODOTSTEAM_VERSION="4.17.1"
GODOTSTEAM_GDE_TAG="v4.17.1-gde"
GODOTSTEAM_ARCHIVE="godotsteam-4.17-gdextension-plugin-4.4.tar.xz"
GODOTSTEAM_BASE_URL="https://codeberg.org/godotsteam/godotsteam/releases/download"

# LimboAI GDExtension plugin (Behavior Trees & State Machines)
LIMBOAI_VERSION="1.7.0"
LIMBOAI_TAG="v1.7.0"
LIMBOAI_ARCHIVE="limboai+v1.7.0.gdextension-4.6.zip"
LIMBOAI_BASE_URL="https://github.com/limbonaut/limboai/releases/download"

# Steam app ID — Fireteam MNG Playtest (App ID 4530870)
STEAM_APP_ID="4530870"

# ── Godot extension registry ──────────────────────────────────────────
# .godot/extension_list.cfg is Godot's authoritative list of GDExtensions.
# Addon install paths are derived from it rather than hardcoded.
EXTENSION_LIST="$SCRIPT_DIR/.godot/extension_list.cfg"
if [[ ! -f "$EXTENSION_LIST" ]]; then
    echo "ERROR: .godot/extension_list.cfg not found. Open the project in Godot at least once to generate it."
    exit 1
fi

# Returns the top-level addon directory for a given extension name pattern.
# e.g. addon_dir "godotsteam" -> "$SCRIPT_DIR/addons/godotsteam"
addon_dir() {
    local pattern="$1"
    local entry
    entry=$(grep -i "$pattern" "$EXTENSION_LIST" | head -1 | sed 's|^res://||')
    [[ -z "$entry" ]] && { echo ""; return; }
    echo "$SCRIPT_DIR/$(echo "$entry" | cut -d'/' -f1-2)"
}

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
ADDON_DIR="$(addon_dir "godotsteam")"
if [[ -z "$ADDON_DIR" ]]; then
    echo "ERROR: godotsteam not found in .godot/extension_list.cfg. Enable the extension in Godot first."
    exit 1
fi

# Ensure required tools are available
for cmd in curl tar xz unzip; do
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

echo "GodotSteam v${GODOTSTEAM_VERSION} installed successfully."

# ── LimboAI GDExtension ──────────────────────────────────────────────
LIMBOAI_URL="${LIMBOAI_BASE_URL}/${LIMBOAI_TAG}/${LIMBOAI_ARCHIVE}"
LIMBOAI_DIR="$(addon_dir "limboai")"
if [[ -z "$LIMBOAI_DIR" ]]; then
    echo "ERROR: limboai not found in .godot/extension_list.cfg. Enable the extension in Godot first."
    exit 1
fi

if [[ -d "$LIMBOAI_DIR" ]]; then
    echo "LimboAI already installed at $LIMBOAI_DIR"
    read -rp "Reinstall? (y/N): " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "Skipped LimboAI."
    else
        rm -rf "$LIMBOAI_DIR"
    fi
fi

if [[ ! -d "$LIMBOAI_DIR" ]]; then
    echo "Downloading LimboAI GDExtension v${LIMBOAI_VERSION}..."
    LIMBOAI_TMP=$(mktemp /tmp/limboai-XXXXXX.zip)
    trap 'rm -f "$TMPFILE" "$LIMBOAI_TMP"' EXIT

    curl -fSL --progress-bar -o "$LIMBOAI_TMP" "$LIMBOAI_URL"

    echo "Extracting to addons/limboai/..."
    unzip -qo "$LIMBOAI_TMP" -d "$SCRIPT_DIR"

    echo "LimboAI v${LIMBOAI_VERSION} installed successfully."
fi

echo ""
echo "Setup complete. Open the project in Godot to verify."
