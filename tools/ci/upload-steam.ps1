param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [Parameter(Mandatory = $false)]
    [string]$BuildOutputDir = "build/windows",
    [Parameter(Mandatory = $false)]
    [string]$SteamBranch = "playtest"
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
if (-not (Test-Path $contentRoot)) {
    throw "Build output directory not found: '$contentRoot'"
}

$steamAppId = Require-Env "STEAM_APP_ID"
$steamDepotIdWindows = Require-Env "STEAM_DEPOT_ID_WINDOWS"
$steamUser = Require-Env "STEAM_BUILDER_USERNAME"
$steamPassword = Require-Env "STEAM_BUILDER_PASSWORD"
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
if ([string]::IsNullOrWhiteSpace($steamGuardCode)) {
    & $steamExe +login $steamUser $steamPassword +run_app_build $generatedAppBuild +quit
} else {
    & $steamExe +set_steam_guard_code $steamGuardCode +login $steamUser $steamPassword +run_app_build $generatedAppBuild +quit
}

if ($LASTEXITCODE -ne 0) {
    throw "SteamCMD upload failed with exit code $LASTEXITCODE"
}

Write-Host "Steam upload complete."
