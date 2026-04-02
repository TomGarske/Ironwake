#!/usr/bin/env bash
set -euo pipefail

# Ironwake — SteamOS / Linux addon setup
# Downloads and installs GDExtension plugins (GodotSteam).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORCE=0
NON_INTERACTIVE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force) FORCE=1 ;;
        --non-interactive) NON_INTERACTIVE=1 ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--force|-f] [--non-interactive]"
            exit 1
            ;;
    esac
    shift
done

# ── Addon versions ────────────────────────────────────────────────────
# GodotSteam GDExtension plugin
GODOTSTEAM_VERSION="4.17.1"
GODOTSTEAM_GDE_TAG="v4.17.1-gde"
GODOTSTEAM_ARCHIVE="godotsteam-4.17-gdextension-plugin-4.4.tar.xz"
GODOTSTEAM_BASE_URL="https://codeberg.org/godotsteam/godotsteam/releases/download"

# Steam app ID — Ironwake Playtest (App ID 4530870)
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

should_reinstall() {
    local name="$1"
    if [[ "$FORCE" -eq 1 ]]; then
        return 0
    fi
    echo "$name already installed; keeping existing install (use --force to reinstall)."
    return 1
}

# Warn if Godot is running (locked files will cause errors on reinstall)
if pgrep -xi "godot" &>/dev/null; then
    echo "WARNING: Godot appears to be running. Please close it before continuing."
    if [[ "$FORCE" -ne 1 && ( "$NON_INTERACTIVE" -eq 1 || ! -t 0 ) ]]; then
        echo "ERROR: Godot is running. Re-run with --force after closing Godot if you want to reinstall addons."
        exit 1
    fi
    if [[ "$FORCE" -eq 1 && ( "$NON_INTERACTIVE" -eq 1 || ! -t 0 ) ]]; then
        echo "Continuing because --force was specified."
    else
        read -rp "Continue anyway? (y/N): " confirm
        if [[ "$confirm" != [yY] ]]; then
            echo "Aborted."
            exit 1
        fi
    fi
fi

DOWNLOAD_URL="${GODOTSTEAM_BASE_URL}/${GODOTSTEAM_GDE_TAG}/${GODOTSTEAM_ARCHIVE}"
ADDON_DIR="$(addon_dir "godotsteam")"
if [[ -z "$ADDON_DIR" ]]; then
    ADDON_DIR="$SCRIPT_DIR/addons/godotsteam"
    echo "godotsteam was not pre-registered; using default path: $ADDON_DIR"
fi

# Ensure required tools are available
for cmd in curl tar xz; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is required but not found. Install it and try again."
        exit 1
    fi
done

if [[ -d "$ADDON_DIR" ]]; then
    echo "GodotSteam already installed at $ADDON_DIR"
    if should_reinstall "GodotSteam"; then
        rm -rf "$ADDON_DIR"
        install_godotsteam=1
    else
        install_godotsteam=0
    fi
else
    install_godotsteam=1
fi

if [[ "$install_godotsteam" -eq 1 ]]; then
    echo "Downloading GodotSteam GDExtension v${GODOTSTEAM_VERSION}..."
    TMPFILE=$(mktemp /tmp/godotsteam-XXXXXX.tar.xz)
    trap 'rm -f "$TMPFILE"' EXIT

    curl -fSL --progress-bar -o "$TMPFILE" "$DOWNLOAD_URL"

    echo "Extracting to addons/godotsteam/..."
    tar -xJf "$TMPFILE" -C "$SCRIPT_DIR"
    echo "GodotSteam v${GODOTSTEAM_VERSION} installed successfully."
else
    echo "Skipped GodotSteam."
fi

# Create steam_appid.txt if it doesn't exist
STEAM_APPID_FILE="$SCRIPT_DIR/steam_appid.txt"
if [[ ! -f "$STEAM_APPID_FILE" ]]; then
    echo "$STEAM_APP_ID" > "$STEAM_APPID_FILE"
    echo "Created steam_appid.txt (app ID: $STEAM_APP_ID)"
fi

echo ""
echo "Setup complete. Open the project in Godot to verify."
