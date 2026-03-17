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
        if (Test-Path $candidate) { return $candidate }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Path }
    }

    throw "Godot CLI not found. Checked env:GODOT4, env:GODOT, godot, and godot4."
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
# Godot export is most reliable with a path relative to project root.
$relativeExportPath = ((Join-Path $OutputDir "FireTeamMNG.exe") -replace "\\", "/").TrimStart("./")
$godotCommand = Resolve-GodotCommand

Write-Host "Exporting with preset '$ExportPresetName' to '$gameExePath'..."
Write-Host "Using Godot CLI: $godotCommand"
$exportOutput = @()
$exitCode = $null
try {
    $exportOutput = & $godotCommand --headless --verbose --path $projectRootResolved --export-release $ExportPresetName $relativeExportPath 2>&1
    $exitCode = $LASTEXITCODE
} catch {
    $exportOutput += $_.Exception.Message
    $exitCode = $LASTEXITCODE
}

if ($exportOutput.Count -gt 0) {
    Write-Host "Godot export output:"
    $exportOutput | ForEach-Object { Write-Host $_ }
}

if ($null -eq $exitCode) {
    # Some command invocation failures do not populate LASTEXITCODE.
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
