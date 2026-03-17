param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [Parameter(Mandatory = $false)]
    [string]$ExportPresetName = "Windows Desktop",
    [Parameter(Mandatory = $false)]
    [string]$OutputDir = "build/windows"
)

$ErrorActionPreference = "Stop"

function Resolve-GodotCommand {
    # Env vars are preferred only if they resolve to a real .exe.
    foreach ($envPath in @($env:GODOT4, $env:GODOT)) {
        if ([string]::IsNullOrWhiteSpace($envPath)) { continue }
        if ($envPath -match '\.exe$' -and (Test-Path $envPath)) { return $envPath }
        if (Test-Path "$envPath.exe") { return "$envPath.exe" }
    }

    # Fallback to command-name lookup. Returning the name (not Source path)
    # lets PowerShell resolve PATH/PATHEXT and invoke hard links correctly.
    foreach ($name in @("godot4", "godot")) {
        if (Get-Command $name -ErrorAction SilentlyContinue) { return $name }
    }

    throw "Godot CLI not found. Set GODOT4/GODOT to an .exe path, or ensure godot/godot4 is in PATH."
}

$projectRootResolved = (Resolve-Path $ProjectRoot).Path
$outputDirResolved = Join-Path $projectRootResolved $OutputDir
$presetTemplatePath = Join-Path $projectRootResolved "tools/ci/export_presets.ci.cfg"
$presetPath = Join-Path $projectRootResolved "export_presets.cfg"

if (-not (Test-Path $presetTemplatePath)) {
    throw "Missing preset template at '$presetTemplatePath'."
}

Copy-Item -Path $presetTemplatePath -Destination $presetPath -Force
New-Item -ItemType Directory -Path $outputDirResolved -Force | Out-Null

$gameExePath = Join-Path $outputDirResolved "FireTeamMNG.exe"
# Native Godot export is more reliable with a project-relative output path.
$relativeExportPath = ((Join-Path $OutputDir "FireTeamMNG.exe") -replace "\\", "/")
$godotCommand = Resolve-GodotCommand

Write-Host "Exporting with preset '$ExportPresetName' to '$gameExePath'..."
Write-Host "Using Godot CLI: $godotCommand"
try {
    $resolved = Get-Command $godotCommand -ErrorAction SilentlyContinue
    if ($resolved) { Write-Host "Resolved CLI path: $($resolved.Source)" }
} catch {}
# Stream Godot output directly to the log (no capture) so every line is visible in CI.
try {
    & $godotCommand --headless --verbose --path $projectRootResolved --export-release $ExportPresetName $relativeExportPath
    $exitCode = $LASTEXITCODE
} catch {
    Write-Host "Godot invocation error: $($_.Exception.Message)"
    $exitCode = $LASTEXITCODE
}

if ($null -eq $exitCode) {
    # Some invocation failures do not populate LASTEXITCODE.
    $exitCode = if ($?) { 0 } else { 1 }
}

if ($exitCode -ne 0) {
    throw "Godot export command failed with exit code $exitCode."
}

if (-not (Test-Path $gameExePath)) {
    $dirListing = (Get-ChildItem -Path $outputDirResolved -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ", "
    if ([string]::IsNullOrWhiteSpace($dirListing)) { $dirListing = "<none>" }
    throw "Export failed: expected executable '$gameExePath' was not created. Output directory files: $dirListing"
}

Write-Host "Export complete."
