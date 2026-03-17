# Steam Playtest CI/CD

This repository includes a GitHub Actions workflow that exports a Windows build and uploads it to Steam whenever `main` is updated.

## Workflow

- File: `.github/workflows/steam-playtest.yml`
- Trigger: push to `main` (and manual `workflow_dispatch`)
- Steps:
  - Export Godot Windows build (`tools/ci/export-windows.ps1`)
  - Upload build to Steam (`tools/ci/upload-steam.ps1`)

## Required GitHub Secrets

Set these in **Repository Settings -> Secrets and variables -> Actions**:

- `STEAM_APP_ID` (your playtest app ID)
- `STEAM_DEPOT_ID_WINDOWS` (Windows depot ID in Steamworks)
- `STEAM_BUILDER_USERNAME` (Steam build account username)
- `STEAM_BUILDER_PASSWORD` (Steam build account password)
- `STEAM_GUARD_CODE` (optional, only if your build account requires it)

## Branch target

By default, uploads set live to Steam branch:

- `playtest`

Change `STEAM_BRANCH` in `.github/workflows/steam-playtest.yml` if needed.
