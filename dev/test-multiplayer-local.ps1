# Two Godot windows for local Steam MP (host left / client right). Set GODOT_EXE or PATH.
$ErrorActionPreference = "Stop"
$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$WindowW = 960
$WindowH = 540

$Godot = $env:GODOT_EXE
if (-not $Godot) {
    $c = Get-Command godot -ErrorAction SilentlyContinue
    if ($c) { $Godot = $c.Source }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) {
    Write-Error "Set GODOT_EXE to Godot 4, or add godot to PATH."
}

$hostArgs = @("--path", $ProjectDir, "--position", "0,0", "--resolution", "${WindowW}x${WindowH}")
$clientArgs = @("--path", $ProjectDir, "--position", "${WindowW},0", "--resolution", "${WindowW}x${WindowH}")

Write-Host "Launching HOST..."
$hp = Start-Process -FilePath $Godot -ArgumentList $hostArgs -PassThru
Start-Sleep -Seconds 2
Write-Host "Launching CLIENT..."
$cp = Start-Process -FilePath $Godot -ArgumentList $clientArgs -PassThru
Write-Host "Host left, client right. Close Godot windows when done."
try {
    Wait-Process -Id $hp.Id, $cp.Id -ErrorAction SilentlyContinue
} finally {
    if (-not $hp.HasExited) { Stop-Process -Id $hp.Id -Force -ErrorAction SilentlyContinue }
    if (-not $cp.HasExited) { Stop-Process -Id $cp.Id -Force -ErrorAction SilentlyContinue }
}
