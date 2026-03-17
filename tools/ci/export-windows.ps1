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
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT4)) { $candidates += $env:GODOT4 }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT)) { $candidates += $env:GODOT }
    # Prefer godot4 over generic godot to avoid old shims.
    $candidates += @("godot4", "godot")

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        # Use Get-Command first — it handles PATH lookup, PATHEXT extension resolution,
        # and correctly resolves hard links / symlinks to their actual executable path.
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $cmd) { return $cmd.Source }
        # Fallback: try path directly and with .exe suffix for absolute paths
        if ($candidate -match '[/\\]') {
            if (Test-Path "$candidate.exe") { return "$candidate.exe" }
            if (Test-Path $candidate) { return $candidate }
        }
    }

    throw "Godot CLI not found. Checked env:GODOT4, env:GODOT, godot4, and godot."
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
$godotCommand = Resolve-GodotCommand

Write-Host "Exporting with preset '$ExportPresetName' to '$gameExePath'..."
Write-Host "Using Godot CLI: $godotCommand"
# Stream Godot output directly to the log (no capture) so every line is visible in CI.
& $godotCommand --headless --verbose --path $projectRootResolved --export-release $ExportPresetName $gameExePath
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    throw "Godot export command failed with exit code $exitCode."
}

if (-not (Test-Path $gameExePath)) {
    $dirListing = (Get-ChildItem -Path $outputDirResolved -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ", "
    if ([string]::IsNullOrWhiteSpace($dirListing)) { $dirListing = "<none>" }
    throw "Export failed: expected executable '$gameExePath' was not created. Output directory files: $dirListing"
}

Write-Host "Export complete."
