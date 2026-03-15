# BurnBridgers — Windows GodotSteam setup
# Downloads and installs the GodotSteam GDExtension plugin.
# Requires: PowerShell 5.1+, Windows 10 1903+ (for built-in tar with xz support)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "addons\addons.cfg"

if (-not (Test-Path $ConfigPath)) {
    Write-Error "addons\addons.cfg not found at $ConfigPath"
    exit 1
}

# Parse the config file (key="value" format)
$Config = @{}
Get-Content $ConfigPath | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)\s*=\s*"(.+)"') {
        $Config[$Matches[1]] = $Matches[2]
    }
}

$Version    = $Config["GODOTSTEAM_VERSION"]
$GdeTag     = $Config["GODOTSTEAM_GDE_TAG"]
$Archive    = $Config["GODOTSTEAM_ARCHIVE"]
$BaseUrl    = $Config["GODOTSTEAM_BASE_URL"]
$DownloadUrl = "$BaseUrl/$GdeTag/$Archive"
$AddonDir   = Join-Path $ScriptDir "addons\godotsteam"

if (Test-Path $AddonDir) {
    Write-Host "GodotSteam already installed at $AddonDir"
    $confirm = Read-Host "Reinstall? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Skipped."
        exit 0
    }
    Remove-Item -Recurse -Force $AddonDir
}

# Check that tar.exe is available (built into Windows 10 1903+)
if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
    Write-Error "tar.exe not found. Windows 10 1903 or later is required."
    exit 1
}

$TmpFile = Join-Path $env:TEMP "godotsteam-$Version.tar.xz"

try {
    Write-Host "Downloading GodotSteam GDExtension v$Version..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TmpFile -UseBasicParsing

    Write-Host "Extracting to addons\godotsteam\..."
    tar -xf $TmpFile -C $ScriptDir

    Write-Host ""
    Write-Host "GodotSteam v$Version installed successfully."
    Write-Host "Open the project in Godot to verify."
}
finally {
    if (Test-Path $TmpFile) {
        Remove-Item $TmpFile -Force
    }
}
