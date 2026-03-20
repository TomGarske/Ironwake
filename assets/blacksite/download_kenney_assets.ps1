# =============================================================================
# Blacksite Containment - Kenney Asset Downloader
# =============================================================================
# Run this script from PowerShell on your Windows machine.
# It will download the required Kenney asset packs and extract them into the
# correct subfolders under assets/blacksite/ in this project.
#
# Usage: Right-click this file → "Run with PowerShell"
#    OR: In PowerShell, cd to the project root and run:
#        .\assets\blacksite\download_kenney_assets.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

# Resolve to the project root (two levels up from this script)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..\..")
$blacksiteAssets = Join-Path $projectRoot "assets\blacksite"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Blacksite Containment - Kenney Downloader" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Project root : $projectRoot"
Write-Host "Asset target : $blacksiteAssets"
Write-Host ""

# ---------------------------------------------------------------------------
# Asset pack definitions
# Each entry: Name, Kenney page slug, destination subfolder, description
# ---------------------------------------------------------------------------
$packs = @(
    @{
        Name        = "Sci-Fi RTS"
        Slug        = "sci-fi-rts"
        Dest        = "models\_kenney_sci-fi-rts"
        Description = "3D models: hover units, mechs, troops - used for DRONE and ESCAPEE meshes"
    },
    @{
        Name        = "Space Kit"
        Slug        = "space-kit"
        Dest        = "models\_kenney_space-kit"
        Description = "3D modular space environment: floors, walls, pillars - ARENA geometry base"
    },
    @{
        Name        = "Space Station Kit"
        Slug        = "space-station-kit"
        Dest        = "models\_kenney_space-station-kit"
        Description = "3D space station pieces: corridors, panels - ARENA detail geometry"
    },
    @{
        Name        = "Modular Space Kit"
        Slug        = "modular-space-kit"
        Dest        = "models\_kenney_modular-space-kit"
        Description = "Compact modular space blocks - optional ARENA obstacles and staging area"
    },
    @{
        Name        = "UI Pack: Sci-Fi"
        Slug        = "ui-pack-sci-fi"
        Dest        = "ui\_kenney_ui-pack-sci-fi"
        Description = "2D sci-fi UI panels, buttons, bars, icons - BLACKSITE HUD base layer"
    },
    @{
        Name        = "Sci-Fi Sounds"
        Slug        = "sci-fi-sounds"
        Dest        = "audio\_kenney_sci-fi-sounds"
        Description = "Laser zaps, beeps, charge hums, UI sounds - ABILITY and HUD audio"
    },
    @{
        Name        = "Interface Sounds"
        Slug        = "interface-sounds"
        Dest        = "audio\_kenney_interface-sounds"
        Description = "UI click, confirm, cancel, notification sounds - MENU and debrief audio"
    }
)

# ---------------------------------------------------------------------------
# Helper: scrape the Kenney asset page and return the .zip download URL
# ---------------------------------------------------------------------------
function Get-KenneyDownloadUrl {
    param([string]$Slug)

    $pageUrl = "https://kenney.nl/assets/$Slug"
    Write-Host "  Fetching page: $pageUrl" -ForegroundColor DarkGray

    try {
        $response = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -TimeoutSec 30
    }
    catch {
        throw "Failed to fetch $pageUrl : $_"
    }

    # Kenney download links look like:
    #   href="/media/pages/assets/<slug>/<hash>/<slug>.zip"
    $pattern = 'href="(/media/pages/assets/' + [regex]::Escape($Slug) + '/[^"]+\.zip)"'
    $match = [regex]::Match($response.Content, $pattern)

    if (-not $match.Success) {
        # Fallback: look for any zip link containing the slug
        $fallback = [regex]::Match($response.Content, 'href="([^"]*' + [regex]::Escape($Slug) + '[^"]*\.zip)"')
        if ($fallback.Success) {
            return "https://kenney.nl" + $fallback.Groups[1].Value
        }
        throw "Could not find download link on $pageUrl - the page structure may have changed."
    }

    return "https://kenney.nl" + $match.Groups[1].Value
}

# ---------------------------------------------------------------------------
# Helper: download a zip and extract it
# ---------------------------------------------------------------------------
function Download-AndExtract {
    param(
        [string]$Url,
        [string]$DestFolder
    )

    $zipPath = Join-Path $env:TEMP ("kenney_" + [System.IO.Path]::GetFileName($Url))

    Write-Host "  Downloading: $Url" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $Url -OutFile $zipPath -UseBasicParsing -TimeoutSec 120

    $sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host "  Downloaded ${sizeMB} MB → $zipPath" -ForegroundColor DarkGray

    if (Test-Path $DestFolder) {
        Write-Host "  Destination exists, skipping extraction (delete folder to re-extract)" -ForegroundColor Yellow
    }
    else {
        New-Item -ItemType Directory -Path $DestFolder -Force | Out-Null
        Write-Host "  Extracting to: $DestFolder" -ForegroundColor DarkGray
        Expand-Archive -Path $zipPath -DestinationPath $DestFolder -Force
    }

    Remove-Item $zipPath -Force
}

# ---------------------------------------------------------------------------
# Main download loop
# ---------------------------------------------------------------------------
$success = @()
$failed  = @()

foreach ($pack in $packs) {
    Write-Host ""
    Write-Host "[$($pack.Name)]" -ForegroundColor White
    Write-Host "  $($pack.Description)" -ForegroundColor Gray

    $destPath = Join-Path $blacksiteAssets $pack.Dest

    if (Test-Path $destPath) {
        Write-Host "  Already downloaded - skipping. (Delete '$($pack.Dest)' to re-download.)" -ForegroundColor Yellow
        $success += $pack.Name
        continue
    }

    try {
        $zipUrl = Get-KenneyDownloadUrl -Slug $pack.Slug
        Download-AndExtract -Url $zipUrl -DestFolder $destPath
        Write-Host "  OK" -ForegroundColor Green
        $success += $pack.Name
    }
    catch {
        Write-Host "  FAILED: $_" -ForegroundColor Red
        $failed += $pack.Name
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Download Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

if ($success.Count -gt 0) {
    Write-Host "Succeeded ($($success.Count)):" -ForegroundColor Green
    $success | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green }
}

if ($failed.Count -gt 0) {
    Write-Host "Failed ($($failed.Count)) - download manually from kenney.nl:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $_ → https://kenney.nl/assets/$($_.ToLower() -replace ' ','-')" -ForegroundColor Red }
}

Write-Host ""
Write-Host "Assets landed in: $blacksiteAssets" -ForegroundColor Cyan
Write-Host "See ASSET_MAPPING.md for how each pack maps to game elements." -ForegroundColor Cyan
Write-Host ""

