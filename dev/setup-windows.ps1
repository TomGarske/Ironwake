# Ironwake — Windows addon setup
# Downloads and installs GDExtension plugins (GodotSteam, LimboAI).
# Requires: PowerShell 5.1+, 7-Zip or Windows tar with xz support (for GodotSteam)

param(
    [switch]$Force,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# ── Addon versions ────────────────────────────────────────────────────
# GodotSteam GDExtension plugin
$GodotSteamVersion = "4.17.1"
$GodotSteamGdeTag  = "v4.17.1-gde"
$GodotSteamArchive = "godotsteam-4.17-gdextension-plugin-4.4.tar.xz"
$GodotSteamBaseUrl = "https://codeberg.org/godotsteam/godotsteam/releases/download"

# LimboAI GDExtension plugin
$LimboAIVersion  = "1.7.0"
$LimboAITag      = "v1.7.0"
$LimboAIArchive  = "limboai+v1.7.0.gdextension-4.6.zip"
$LimboAIBaseUrl  = "https://github.com/limbonaut/limboai/releases/download"

# Steam app ID — Ironwake Playtest (App ID 4530870)
$SteamAppId = "4530870"

# ── Godot extension registry ──────────────────────────────────────────
# .godot\extension_list.cfg is Godot's authoritative list of GDExtensions.
# Addon install paths are derived from it rather than hardcoded.
$ExtensionList = Join-Path $ScriptDir ".godot\extension_list.cfg"
if (-not (Test-Path $ExtensionList)) {
    Write-Error ".godot\extension_list.cfg not found. Open the project in Godot at least once to generate it."
    exit 1
}

function Get-AddonDir {
    param([string]$Pattern)
    $line = Get-Content $ExtensionList | Where-Object { $_ -imatch $Pattern } | Select-Object -First 1
    if (-not $line) { return $null }
    $rel = $line -replace '^res://', ''
    $parts = $rel -split '/'
    return Join-Path $ScriptDir ($parts[0] + '\' + $parts[1])
}

function Should-Reinstall {
    param([string]$ComponentName)

    if ($Force) { return $true }
    Write-Host "$ComponentName already installed; keeping existing install (use -Force to reinstall)."
    return $false
}

# Warn if Godot is running (locked DLLs will cause errors on reinstall)
$GodotProc = Get-Process -Name "Godot*" -ErrorAction SilentlyContinue
if ($GodotProc) {
    Write-Host "WARNING: Godot appears to be running. Please close it before continuing."
    if (-not $Force -and ($NonInteractive -or -not [Environment]::UserInteractive)) {
        Write-Error "Godot is running. Re-run with -Force after closing Godot if you want to reinstall addons."
        exit 1
    }
    if ($Force -and ($NonInteractive -or -not [Environment]::UserInteractive)) {
        Write-Host "Continuing because -Force was specified."
    } else {
        $confirm = Read-Host "Continue anyway? (y/N)"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "Aborted by user."
            exit 1
        }
    }
}

$Version     = $GodotSteamVersion
$GdeTag      = $GodotSteamGdeTag
$Archive     = $GodotSteamArchive
$BaseUrl     = $GodotSteamBaseUrl
$DownloadUrl = "$BaseUrl/$GdeTag/$Archive"
$AddonDir    = Get-AddonDir "godotsteam"
if (-not $AddonDir) {
    $AddonDir = Join-Path $ScriptDir "addons\godotsteam"
    Write-Host "godotsteam was not pre-registered; using default path: $AddonDir"
}
$GodotSteamRequiredLib = Join-Path $AddonDir "win64\libgodotsteam.windows.template_release.x86_64.dll"

if (Test-Path $AddonDir) {
    Write-Host "GodotSteam already installed at $AddonDir"
    if (-not (Test-Path $GodotSteamRequiredLib)) {
        Write-Host "GodotSteam install appears incomplete (missing Windows runtime DLL); repairing install."
        $installGodotSteam = $true
    } else {
        $installGodotSteam = Should-Reinstall "GodotSteam"
    }
    if ($installGodotSteam -and $Force) {
        Remove-Item -Recurse -Force $AddonDir
    }
} else {
    $installGodotSteam = $true
}

# Locate an extraction tool that supports .tar.xz
$7zPaths = @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe"
)
$7zExe = $null
foreach ($p in $7zPaths) {
    if (Test-Path $p) { $7zExe = $p; break }
}
if (-not $7zExe -and (Get-Command 7z -ErrorAction SilentlyContinue)) {
    $7zExe = "7z"
}

$HasTar = [bool](Get-Command tar -ErrorAction SilentlyContinue)

if (-not $7zExe -and -not $HasTar) {
    Write-Error "No extraction tool found. Install 7-Zip (https://7-zip.org) or use Windows 10 1903+."
    exit 1
}

$TmpFile = Join-Path $env:TEMP "godotsteam-$Version.tar.xz"
$TmpTar  = Join-Path $env:TEMP "godotsteam-$Version.tar"

if ($installGodotSteam) {
    try {
        Write-Host "Downloading GodotSteam GDExtension v$Version..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $TmpFile -UseBasicParsing

        Write-Host "Extracting to addons\godotsteam\..."

        $extracted = $false

        # 7z requires two steps: .tar.xz -> .tar -> files
        if ($7zExe) {
            & $7zExe x $TmpFile "-o$env:TEMP" -y | Out-Null
            if (Test-Path $TmpTar) {
                & $7zExe x $TmpTar "-o$ScriptDir" -y | Out-Null
                $extracted = $true
            }
        }

        # Fall back to built-in tar
        if (-not $extracted -and $HasTar) {
            tar -xf $TmpFile -C $ScriptDir 2>$null
            if ($LASTEXITCODE -eq 0) {
                $extracted = $true
            }
        }

        if (-not $extracted) {
            Write-Error "Extraction failed. Install 7-Zip (https://7-zip.org) and try again."
            exit 1
        }

        Write-Host "GodotSteam v$Version installed successfully."
    }
    finally {
        if (Test-Path $TmpFile) { Remove-Item $TmpFile -Force }
        if (Test-Path $TmpTar)  { Remove-Item $TmpTar  -Force }
    }
} else {
    Write-Host "Skipped GodotSteam."
}

# ── LimboAI ────────────────────────────────────────────────────────────
$LimboDownloadUrl = "$LimboAIBaseUrl/$LimboAITag/$LimboAIArchive"
$LimboAddonDir    = Get-AddonDir "limboai"
if (-not $LimboAddonDir) {
    $LimboAddonDir = Join-Path $ScriptDir "addons\limboai"
    Write-Host "limboai was not pre-registered; using default path: $LimboAddonDir"
}
$LimboRequiredLib = Join-Path $LimboAddonDir "bin\liblimboai.windows.template_release.x86_64.dll"

if (Test-Path $LimboAddonDir) {
    Write-Host "LimboAI already installed at $LimboAddonDir"
    if (-not (Test-Path $LimboRequiredLib)) {
        Write-Host "LimboAI install appears incomplete (missing Windows runtime DLL); repairing install."
        $installLimboAI = $true
    } else {
        $installLimboAI = Should-Reinstall "LimboAI"
    }
    if ($installLimboAI -and $Force) {
        Remove-Item -Recurse -Force $LimboAddonDir
    }
} else {
    $installLimboAI = $true
}

$LimboTmpFile = Join-Path $env:TEMP "limboai-$LimboAIVersion.zip"

if ($installLimboAI) {
    try {
        Write-Host "Downloading LimboAI GDExtension v$LimboAIVersion..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $LimboDownloadUrl -OutFile $LimboTmpFile -UseBasicParsing

        Write-Host "Extracting to addons\limboai\..."
        Expand-Archive -Path $LimboTmpFile -DestinationPath $ScriptDir -Force

        Write-Host "LimboAI v$LimboAIVersion installed successfully."
    }
    finally {
        if (Test-Path $LimboTmpFile) { Remove-Item $LimboTmpFile -Force }
    }
} else {
    Write-Host "Skipped LimboAI."
}

# Create steam_appid.txt if it doesn't exist
$AppIdFile = Join-Path $ScriptDir "steam_appid.txt"
if (-not (Test-Path $AppIdFile)) {
    $SteamAppId | Out-File -FilePath $AppIdFile -Encoding ascii -NoNewline
    Write-Host "Created steam_appid.txt (app ID: $SteamAppId)"
}

Write-Host ""
Write-Host "Setup complete. Open the project in Godot to verify."
