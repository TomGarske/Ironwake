param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"

# ── Versions (keep in sync with setup-windows.ps1) ────────────────────────────
$GodotSteamTag     = "v4.17.1-gde"
$GodotSteamArchive = "godotsteam-4.17-gdextension-plugin-4.4.tar.xz"
$GodotSteamUrl     = "https://codeberg.org/godotsteam/godotsteam/releases/download/$GodotSteamTag/$GodotSteamArchive"

# ── Helpers ───────────────────────────────────────────────────────────────────
function Get-7z {
    $candidates = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    $cmd = Get-Command 7z -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Path }
    return $null
}

# ── GodotSteam (.tar.xz) ──────────────────────────────────────────────────────
$godotSteamDest = Join-Path $ProjectRoot "addons\godotsteam"
if (Test-Path $godotSteamDest) {
    Write-Host "GodotSteam already present — skipping download."
} else {
    Write-Host "Downloading GodotSteam $GodotSteamTag..."
    $tmpXz  = Join-Path $env:TEMP "godotsteam.tar.xz"
    $tmpTar = Join-Path $env:TEMP "godotsteam.tar"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $GodotSteamUrl -OutFile $tmpXz -UseBasicParsing

        Write-Host "Extracting GodotSteam..."
        $7z = Get-7z
        if ($7z) {
            & $7z x $tmpXz "-o$env:TEMP" -y | Out-Null
            if (-not (Test-Path $tmpTar)) { throw "7z did not produce a .tar file from $tmpXz" }
            & $7z x $tmpTar "-o$ProjectRoot" -y | Out-Null
        } elseif (Get-Command tar -ErrorAction SilentlyContinue) {
            tar -xf $tmpXz -C $ProjectRoot
            if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE" }
        } else {
            throw "No extraction tool found for .tar.xz (install 7-Zip or use Windows 10 1903+)."
        }

        if (-not (Test-Path $godotSteamDest)) {
            throw "GodotSteam extraction succeeded but '$godotSteamDest' was not created."
        }
        Write-Host "GodotSteam installed to $godotSteamDest"
    } finally {
        if (Test-Path $tmpXz)  { Remove-Item $tmpXz  -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tmpTar) { Remove-Item $tmpTar -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host "GDExtension setup complete."
