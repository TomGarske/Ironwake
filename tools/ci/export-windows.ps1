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
    $candidates += @("godot", "godot4")

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
$godotCommand = Resolve-GodotCommand

Write-Host "Exporting with preset '$ExportPresetName' to '$gameExePath'..."
Write-Host "Using Godot CLI: $godotCommand"
& $godotCommand --headless --path $projectRootResolved --export-release $ExportPresetName $gameExePath

if ($LASTEXITCODE -ne 0) {
    throw "Godot export command failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path $gameExePath)) {
    $dirListing = (Get-ChildItem -Path $outputDirResolved -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ", "
    if ([string]::IsNullOrWhiteSpace($dirListing)) { $dirListing = "<none>" }
    throw "Export failed: expected executable '$gameExePath' was not created. Output directory files: $dirListing"
}

Write-Host "Export complete."
