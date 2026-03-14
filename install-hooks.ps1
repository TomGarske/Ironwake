param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceHook = Join-Path $repoRoot ".githooks/pre-commit"
$targetDir = Join-Path $repoRoot ".git/hooks"
$targetHook = Join-Path $targetDir "pre-commit"

if (!(Test-Path $sourceHook)) {
    throw "Missing hook source file: $sourceHook"
}

if (!(Test-Path $targetDir)) {
    throw "Missing git hooks directory: $targetDir"
}

Copy-Item -Path $sourceHook -Destination $targetHook -Force

Write-Host "Installed pre-commit hook at $targetHook"
Write-Host "This hook blocks commits on main/master and only allows feature/* branches."
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceHook = Join-Path $repoRoot ".githooks/pre-commit"
$targetDir = Join-Path $repoRoot ".git/hooks"
$targetHook = Join-Path $targetDir "pre-commit"

if (!(Test-Path $sourceHook)) {
    throw "Missing hook source file: $sourceHook"
}

if (!(Test-Path $targetDir)) {
    throw "Missing git hooks directory: $targetDir"
}

Copy-Item -Path $sourceHook -Destination $targetHook -Force

Write-Host "Installed pre-commit hook at $targetHook"
Write-Host "This hook blocks commits on main/master and only allows feature/* branches."
