#Requires -Version 5.1
<#
.SYNOPSIS
    Launches the BurnBridgers Godot project.

.PARAMETER Mode
    editor  - Open the Godot editor with this project (default)
    offline - Open the editor and immediately run in offline test mode via --scene arg
    debug   - Run via console binary and stream logs to file (best for multiplayer/Steam issues)

.EXAMPLE
    .\run.ps1
    .\run.ps1 -Mode offline
    .\run.ps1 -Mode debug
#>
param(
    [ValidateSet("editor", "offline", "debug")]
    [string]$Mode = "editor",
    [switch]$NoLogCapture,
    [switch]$NoLogWindow,
    [int]$AppId = 0
)

$ProjectRoot = $PSScriptRoot

# ---------------------------------------------------------------------------
# 1. Find Godot executable
# ---------------------------------------------------------------------------
$Godot = $null

# First: check PATH (works after shell restart post-winget install)
$onPath = Get-Command godot -ErrorAction SilentlyContinue
if ($onPath) {
    $Godot = $onPath.Source
}

# Second: check WinGet package location (works without shell restart)
if (-not $Godot) {
    $wingetPkg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine*" `
        -Recurse -Filter "Godot_v*win64.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "console" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($wingetPkg) {
        $Godot = $wingetPkg.FullName
    }
}

# Third: check common manual install locations
if (-not $Godot) {
    $candidates = @(
        "C:\Program Files\Godot\Godot_v4*.exe",
        "C:\Godot\Godot_v4*.exe",
        "$env:USERPROFILE\Godot\Godot_v4*.exe"
    )
    foreach ($pattern in $candidates) {
        $found = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $Godot = $found.FullName; break }
    }
}

if (-not $Godot) {
    Write-Error @"
Godot executable not found.

Install it with:
  winget install --id GodotEngine.GodotEngine --exact

Then restart your terminal and try again.
"@
    exit 1
}

Write-Host "[BurnBridgers] Using Godot: $Godot" -ForegroundColor Cyan

# Prefer console binary in debug mode so script errors are visible.
$GodotConsole = $Godot -replace '\.exe$', '_console.exe'
if ($Mode -eq "debug" -and -not (Test-Path $GodotConsole)) {
    Write-Warning "[BurnBridgers] Console binary not found at: $GodotConsole. Falling back to standard executable."
    $GodotConsole = $Godot
}

# ---------------------------------------------------------------------------
# 2. Check required files
# ---------------------------------------------------------------------------
$appIdFile = Join-Path $ProjectRoot "steam_appid.txt"

if ($AppId -le 0) {
    $envAppId = [int]($env:BURNBRIDGERS_STEAM_APPID)
    if ($envAppId -gt 0) {
        $AppId = $envAppId
    }
}

if ($AppId -gt 0) {
    Set-Content -Path $appIdFile -Value "$AppId" -NoNewline
    Write-Host "[BurnBridgers] Using explicit Steam App ID: $AppId" -ForegroundColor Green
} elseif (-not (Test-Path $appIdFile)) {
    Write-Host "[BurnBridgers] Creating steam_appid.txt (app ID 480 for dev)..." -ForegroundColor Yellow
    Set-Content -Path $appIdFile -Value "480" -NoNewline
}

if (Test-Path $appIdFile) {
    $activeAppId = (Get-Content -Path $appIdFile -Raw).Trim()
    if ($activeAppId -eq "480") {
        Write-Warning "[BurnBridgers] Active Steam App ID is 480 (Spacewar). Invites will show Spacewar until you use your real BurnBridgers app ID."
    } else {
        Write-Host "[BurnBridgers] Active Steam App ID: $activeAppId" -ForegroundColor Green
    }
}

$gdextension = Join-Path $ProjectRoot "addons\godotsteam\godotsteam.gdextension"
if (-not (Test-Path $gdextension)) {
    Write-Warning @"
GodotSteam GDExtension not found at addons/godotsteam/godotsteam.gdextension.
The game will fail to start. Run the setup steps in SETUP.md first.
"@
}

# ---------------------------------------------------------------------------
# 3. Launch
# ---------------------------------------------------------------------------
$args = @("--path", $ProjectRoot)

if ($Mode -eq "offline") {
    # Pass a flag via a user arg so the game can read it (future) —
    # for now, editor opens normally; press Test (Offline) in the main menu.
    Write-Host "[BurnBridgers] Opening editor. Press 'Test (Offline)' in the main menu to skip Steam." -ForegroundColor Green
}

if ($Mode -eq "debug") {
    $args += @("--verbose")
    $logsDir = Join-Path $ProjectRoot "logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -Path $logsDir -ItemType Directory | Out-Null
    }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logFile = Join-Path $logsDir "godot-debug-$timestamp.log"

    Write-Host "[BurnBridgers] Launching debug mode with live logs..." -ForegroundColor Cyan
    Write-Host "[BurnBridgers] Log file: $logFile" -ForegroundColor Yellow

    if ($NoLogCapture) {
        & $GodotConsole @args
        $exitCode = $LASTEXITCODE
    } else {
        if (-not $NoLogWindow) {
            $tailCommand = "Get-Content -Path '$logFile' -Wait"
            Start-Process powershell -ArgumentList @("-NoExit", "-Command", $tailCommand)
            Write-Host "[BurnBridgers] Opened live log window." -ForegroundColor Green
        }
        # Tee both stdout/stderr so errors can be shared for debugging.
        # Convert to plain text to avoid PowerShell NativeCommandError wrappers.
        & $GodotConsole @args 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath $logFile
        $exitCode = $LASTEXITCODE
    }

    # Check for crash trace files after process exits
    # Check even on normal exit (0) in case crash happened but exit code was misleading
    $checkForCrashes = $true
    if ($checkForCrashes) {
        $crashWindowMinutes = 10  # Look for crash files created in the last 10 minutes
        $startTime = (Get-Date).AddMinutes(-$crashWindowMinutes)
        
        Write-Host "[BurnBridgers] Checking for crash traces (files modified in last $crashWindowMinutes minutes)..." -ForegroundColor Yellow
        
        # Common locations for Godot crash dumps and trace files
        $crashPatterns = @(
            @{ Path = $ProjectRoot; Patterns = @("crash_*.dmp", "godot_*.dmp", "*.dmp", "crash_*.txt", "error_*.log") },
            @{ Path = Join-Path $env:LOCALAPPDATA "Godot"; Patterns = @("crash_*.dmp", "godot_*.dmp", "*.dmp") },
            @{ Path = Join-Path $env:APPDATA "Godot"; Patterns = @("crash_*.dmp", "godot_*.dmp", "*.dmp") }
        )
        
        $foundTraces = @()
        foreach ($location in $crashPatterns) {
            $basePath = $location.Path
            if (-not (Test-Path $basePath)) {
                continue
            }
            foreach ($pattern in $location.Patterns) {
                $fullPattern = Join-Path $basePath $pattern
                try {
                    $traces = Get-ChildItem -Path $fullPattern -ErrorAction SilentlyContinue | 
                        Where-Object { $_.LastWriteTime -gt $startTime }
                    if ($traces) {
                        $foundTraces += $traces
                    }
                } catch {
                    # Pattern might not match any files, continue
                }
            }
        }
        
        # Remove duplicates (same file found via multiple patterns)
        $foundTraces = $foundTraces | Sort-Object FullName -Unique
        
        if ($foundTraces.Count -gt 0) {
            Write-Host "[BurnBridgers] Found $($foundTraces.Count) crash trace file(s). Copying to logs directory..." -ForegroundColor Red
            
            $traceInfo = @()
            foreach ($trace in $foundTraces) {
                $traceDest = Join-Path $logsDir "crash-$timestamp-$($trace.Name)"
                try {
                    Copy-Item -Path $trace.FullName -Destination $traceDest -Force
                    $traceInfo += "Crash trace: $traceDest (source: $($trace.FullName))"
                    Write-Host "[BurnBridgers] Copied crash trace: $traceDest" -ForegroundColor Red
                } catch {
                    Write-Warning "[BurnBridgers] Failed to copy crash trace $($trace.FullName): $_"
                    $traceInfo += "Crash trace (copy failed): $($trace.FullName)"
                }
            }
            
            # Append trace file references to the log file
            if (Test-Path $logFile) {
                Add-Content -Path $logFile -Value "`n========== CRASH TRACE DETECTED =========="
                Add-Content -Path $logFile -Value "Exit code: $exitCode"
                Add-Content -Path $logFile -Value "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                Add-Content -Path $logFile -Value "Found $($foundTraces.Count) crash trace file(s):"
                foreach ($info in $traceInfo) {
                    Add-Content -Path $logFile -Value "  $info"
                }
                Add-Content -Path $logFile -Value "==========================================`n"
            }
        } elseif ($exitCode -ne 0 -and $exitCode -ne $null) {
            Write-Host "[BurnBridgers] Process exited with non-zero code ($exitCode) but no crash traces found." -ForegroundColor Yellow
        }
    }
    
    exit $exitCode
}

Write-Host "[BurnBridgers] Launching... (mode: $Mode)" -ForegroundColor Cyan
Start-Process -FilePath $Godot -ArgumentList $args
