# Debug Visualization and Telemetry — Combat Requirements

**Project:** Naval Game
**System:** Combat Debug Instrumentation
**Engine:** Godot (GDScript)
**Date:** 2026-03-29
**Version:** 1.0

---

## 1. Purpose

This document specifies the debugging and visualization tools needed to understand and tune the combat AI and broadside quality systems. All debug features must be easy to toggle on/off.

**Dependencies:**
- `req-combat-loop-v1.md` — broadside quality, engagement bands
- `req-ai-naval-bot-v1.md` — bot behavior tree, blackboard variables

---

## 2. On-Screen Debug HUD

Add an optional debug HUD text overlay for the bot showing:

| Field | Source |
|-------|--------|
| Current BT state | Behavior tree active node |
| Current maneuver | `last_maneuver` blackboard variable |
| Distance to target | `distance_to_target` |
| Target bearing | `target_bearing_degrees` |
| Broadside score (port) | `broadside_quality_port` |
| Broadside score (starboard) | `broadside_quality_starboard` |
| Chosen side | `best_broadside_side` |
| Battery loaded state | Port/starboard loaded booleans |
| Reason not firing | `fire_block_reason` |
| Current range band | Too close / preferred / too far |
| Reposition timer | Remaining reposition duration |
| Stuck state | Whether stuck recovery is active |

### 2.1 Toggle

The HUD must be togglable via a debug key or exported boolean. It should not render in release builds.

---

## 3. Debug Draw Overlays

Add optional line/arc overlays drawn in the game world:

| Overlay | Description |
|---------|-------------|
| Line to target | From bot to target ship |
| Desired heading | Direction the bot wants to face |
| Current forward vector | Ship's actual forward direction |
| Preferred broadside side | Visual indicator of chosen port/starboard |
| Engagement band circles | Circles at minimum_safe_range, preferred range bounds, and maximum_practical_range around target or self |
| Firing arc visualization | The valid broadside arc wedge (if easy to support) |

### 3.1 Toggle

Draw overlays must be togglable independently of the HUD text. Use an exported boolean or debug key.

---

## 4. Debug Logging

Add concise debug logs (using `print` or a lightweight logging wrapper) for:

| Event | Log Content |
|-------|-------------|
| Firing decision | Side, quality score, reason |
| Pass start | Maneuver type, target distance |
| Reposition start | Turn direction, expected duration |
| Reposition end | Duration, new distance to target |
| Stuck recovery | Trigger reason, recovery action |
| Side-switch choice | Old side, new side, reason |

### 4.1 Toggle

Logging must be togglable via an exported boolean. Off by default to avoid console spam.

---

## 5. Implementation Notes

- Debug visualization should be implemented as a separate node or component that can be attached to any ship
- It reads from the same blackboard and evaluator data that the AI uses
- It must not affect gameplay behavior (read-only)
- Prefer Godot's `_draw()` or `CanvasLayer` for overlays depending on whether world-space or screen-space is more appropriate

---

## 6. Out of Scope

- Performance profiling tools
- Replay system
- Network debug tools
- Automated testing harness
