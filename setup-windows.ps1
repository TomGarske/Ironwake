# BurnBridgers — Windows GodotSteam setup
# Downloads and installs the GodotSteam GDExtension plugin.
# Requires: PowerShell 5.1+, 7-Zip or Windows tar with xz support

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

try {
    Write-Host "Downloading GodotSteam GDExtension v$Version..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TmpFile -UseBasicParsing

    Write-Host "Extracting to addons\godotsteam\..."

    $extracted = $false

    # Try 7-Zip first (most reliable for .tar.xz on Windows)
    if ($7zExe) {
        # 7z requires two steps: .tar.xz -> .tar -> files
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

    Write-Host ""
    Write-Host "GodotSteam v$Version installed successfully."
    Write-Host "Open the project in Godot to verify."
}
finally {
    if (Test-Path $TmpFile) { Remove-Item $TmpFile -Force }
    if (Test-Path $TmpTar)  { Remove-Item $TmpTar  -Force }
}
