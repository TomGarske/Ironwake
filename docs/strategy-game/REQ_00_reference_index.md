# Strategy Game Reference Index

This document set is the canonical reference for the `strategy_game` mode.

Use these docs as the source of truth when updating:

- `res://scripts/strategy_game.gd`
- `res://scenes/game/strategy/strategy_game.tscn`
- strategy support systems (terrain editing/registry, mode routing, strategy HUD)

## Reference Documents

1. `REQ_01_vision_and_architecture.md`
2. `REQ_02_systems_and_data_contracts.md`

## Update Rule

When behavior changes in the strategy mode:

1. Update the relevant strategy doc first (or in the same change).
2. Keep naming aligned between docs and runtime symbols.
3. Document new exported vars, signals, and data contracts.
4. Call out multiplayer assumptions explicitly.
