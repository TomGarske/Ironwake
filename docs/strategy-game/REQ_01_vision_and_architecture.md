# Strategy Game: Vision and Architecture

## Purpose

The strategy mode provides a hex-based command layer focused on territory, terrain, and tactical planning.

## Player Fantasy

- Command the map from a strategic perspective.
- Shape terrain to create defensive and offensive advantages.
- Make deliberate positional decisions over twitch execution.

## Core Mode Goals

- Readable hex map state at all times.
- Fast edit/inspect loop for terrain and cells.
- Deterministic state updates suitable for multiplayer authority.

## Mode Boundaries

The strategy mode owns:

- Hex map state and terrain typing.
- Strategy-mode UI and map interaction flow.
- Mode-specific scene and script behavior.

The strategy mode does not own:

- Cross-mode bootstrap and phase transitions (owned by autoload managers).
- Non-strategy scene logic.

## Primary Runtime Surfaces

- Scene: `res://scenes/game/strategy/strategy_game.tscn`
- Script: `res://scripts/strategy_game.gd`
- Related UI tooling: `res://scripts/ui/terrain_creator.gd`
- Terrain registry: `res://scripts/autoload/terrain_definitions.gd`

## Integration Notes

- Multiplayer should remain host-authoritative for map state mutation.
- Any client-facing edit operation should route through authoritative state application.
- New strategy systems should define explicit data contracts (ids, terrain keys, event payloads).
