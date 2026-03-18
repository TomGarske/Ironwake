param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [Parameter(Mandatory = $false)]
    [string]$BuildOutputDir = "build/windows",
    [Parameter(Mandatory = $false)]
    [string]$SteamBranch = "playtest",
    [Parameter(Mandatory = $false)]
    [switch]$PrepareOnly,
    [Parameter(Mandatory = $false)]
    [switch]$SkipSteamCmdUpdate
)

$ErrorActionPreference = "Stop"

function Require-Env {
    param([string]$Name)
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing required environment variable: $Name"
    }
    return $value
}

$projectRootResolved = (Resolve-Path $ProjectRoot).Path
$contentRoot = Join-Path $projectRootResolved $BuildOutputDir
if (-not $PrepareOnly -and -not (Test-Path $contentRoot)) {
    throw "Build output directory not found: '$contentRoot'"
}

$steamAppId = Require-Env "STEAM_APP_ID"
$steamDepotIdWindows = Require-Env "STEAM_DEPOT_ID_WINDOWS"
$steamUser = Require-Env "STEAM_USERNAME"
$steamPassword = Require-Env "STEAM_PASSWORD"
$steamTotpSecret = [Environment]::GetEnvironmentVariable("STEAM_TOTP_SECRET")
$steamGuardCode = [Environment]::GetEnvironmentVariable("STEAM_GUARD_CODE")

$steamDir = Join-Path $env:RUNNER_TEMP "steamcmd"
New-Item -ItemType Directory -Path $steamDir -Force | Out-Null
$steamZip = Join-Path $steamDir "steamcmd.zip"
$steamExe = Join-Path $steamDir "steamcmd.exe"

if (-not (Test-Path $steamExe)) {
    Write-Host "Downloading SteamCMD..."
    Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile $steamZip -UseBasicParsing
    Expand-Archive -Path $steamZip -DestinationPath $steamDir -Force
}

# Generate a Steam Guard TOTP code from the shared secret.
# Steam uses a non-standard TOTP: HMAC-SHA1, 30s period, custom charset, 5-char codes.
function Get-SteamGuardCode {
    param([string]$SharedSecret)

    $secretBytes = [Convert]::FromBase64String($SharedSecret)
    $time = [long][Math]::Floor(([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) / 30)
    $timeBytes = [byte[]]::new(8)
    for ($i = 7; $i -ge 0; $i--) {
        $timeBytes[$i] = [byte]($time -band 0xFF)
        $time = $time -shr 8
    }

    $hmac = New-Object System.Security.Cryptography.HMACSHA1
    $hmac.Key = $secretBytes
    $hash = $hmac.ComputeHash($timeBytes)

    $offset = $hash[19] -band 0x0F
    $code = (($hash[$offset] -band 0x7F) -shl 24) -bor
            (($hash[$offset + 1] -band 0xFF) -shl 16) -bor
            (($hash[$offset + 2] -band 0xFF) -shl 8) -bor
             ($hash[$offset + 3] -band 0xFF)

    $chars = "23456789BCDFGHJKMNPQRTVWXY"
    $guardCode = ""
    for ($i = 0; $i -lt 5; $i++) {
        $guardCode += $chars[$code % $chars.Length]
        $code = [Math]::Floor($code / $chars.Length)
    }

    return $guardCode
}

if ($SkipSteamCmdUpdate) {
    Write-Host "Skipping SteamCMD self-update."
} else {
    # Run SteamCMD once to let it self-update.
    Write-Host "Running SteamCMD self-update..."
    & $steamExe +quit
}

# Resolve Steam Guard code: prefer manual code (workflow_dispatch), then TOTP secret
if (-not [string]::IsNullOrWhiteSpace($steamGuardCode)) {
    $guardCode = $steamGuardCode
    Write-Host "Using manually provided Steam Guard code."
} elseif (-not [string]::IsNullOrWhiteSpace($steamTotpSecret)) {
    $guardCode = Get-SteamGuardCode -SharedSecret $steamTotpSecret
    Write-Host "Generated Steam Guard code from TOTP secret."
} else {
    throw "No Steam Guard code available. Provide a code via workflow_dispatch or set STEAM_TOTP_SECRET."
}

if ($PrepareOnly) {
    Write-Host "Validating Steam credentials and guard code..."
    & $steamExe +set_steam_guard_code $guardCode +login $steamUser $steamPassword +quit

    if ($LASTEXITCODE -ne 0) {
        throw "SteamCMD auth validation failed with exit code $LASTEXITCODE"
    }

    Write-Host "Steam authentication is ready."
    return
}

$templateAppBuild = Join-Path $projectRootResolved "tools/steam/app_build_template.vdf"
$templateDepotBuild = Join-Path $projectRootResolved "tools/steam/depot_build_windows_template.vdf"
if (-not (Test-Path $templateAppBuild)) { throw "Missing $templateAppBuild" }
if (-not (Test-Path $templateDepotBuild)) { throw "Missing $templateDepotBuild" }

$generatedDir = Join-Path $env:RUNNER_TEMP "steam_build"
New-Item -ItemType Directory -Path $generatedDir -Force | Out-Null
$generatedAppBuild = Join-Path $generatedDir "app_build.vdf"
$generatedDepotBuild = Join-Path $generatedDir "depot_build_windows.vdf"

$description = "GitHub Actions build $($env:GITHUB_RUN_NUMBER) - $($env:GITHUB_SHA)"

$appBuildText = Get-Content $templateAppBuild -Raw
$appBuildText = $appBuildText.Replace("__APP_ID__", $steamAppId)
$appBuildText = $appBuildText.Replace("__DESC__", $description)
$appBuildText = $appBuildText.Replace("__SETLIVE__", $SteamBranch)
$appBuildText = $appBuildText.Replace("__CONTENT_ROOT__", $contentRoot)
$appBuildText = $appBuildText.Replace("__DEPOT_ID_WINDOWS__", $steamDepotIdWindows)
Set-Content -Path $generatedAppBuild -Value $appBuildText -NoNewline

$depotBuildText = Get-Content $templateDepotBuild -Raw
$depotBuildText = $depotBuildText.Replace("__DEPOT_ID_WINDOWS__", $steamDepotIdWindows)
Set-Content -Path $generatedDepotBuild -Value $depotBuildText -NoNewline

Write-Host "Uploading build to Steam app $steamAppId (branch: $SteamBranch)..."
& $steamExe +set_steam_guard_code $guardCode +login $steamUser $steamPassword +run_app_build $generatedAppBuild +quit

if ($LASTEXITCODE -ne 0) {
    throw "SteamCMD upload failed with exit code $LASTEXITCODE"
}

Write-Host "Steam upload complete."
