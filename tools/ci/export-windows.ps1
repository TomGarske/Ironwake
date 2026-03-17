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
    # chickensoft-games/setup-godot installs Godot to $env:USERPROFILE\godot\
    #
    # The Mono build (use-dotnet: true) includes TWO executables:
    #   Godot_v*_mono_win64.exe         <- GUI subsystem, no stdout in CI
    #   Godot_v*_mono_win64_console.exe <- Console subsystem, stdout works!
    #
    # The setup-godot action hard-links the GUI exe as 'godot' (no .exe) and
    # calling any no-extension binary by path/name silently fails in PowerShell
    # on Windows (LASTEXITCODE stays null, no output).
    #
    # Solution: find the _console.exe directly by path.
    $godotInstallDir = Join-Path $env:USERPROFILE "godot"
    if (Test-Path $godotInstallDir) {
        $console = Get-ChildItem $godotInstallDir -Recurse -Filter "*_console.exe" `
            -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($console) { return $console.FullName }

        # No console exe (standard build): fall back to any Godot_v*.exe
        $any = Get-ChildItem $godotInstallDir -Recurse -Filter "Godot_v*.exe" `
            -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($any) { return $any.FullName }
    }

    throw "Godot CLI not found. Expected Godot install at '$godotInstallDir'."
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
# Stream directly — the console exe writes to inherited stdout/stderr handles.
& $godotCommand --headless --verbose --path $projectRootResolved --export-release $ExportPresetName $gameExePath
$exitCode = $LASTEXITCODE
if ($null -eq $exitCode) { $exitCode = 1 }

if ($exitCode -ne 0) {
    throw "Godot export command failed with exit code $exitCode."
}

if (-not (Test-Path $gameExePath)) {
    $dirListing = (Get-ChildItem -Path $outputDirResolved -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ", "
    if ([string]::IsNullOrWhiteSpace($dirListing)) { $dirListing = "<none>" }
    throw "Export failed: expected executable '$gameExePath' was not created. Output directory files: $dirListing"
}

Write-Host "Export complete."
