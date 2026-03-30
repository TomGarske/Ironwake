# Naval Combat Prototype — Weapons Layer Requirements (v1.0)

## Intent

Shots are deliberate, readable, and earned through positioning, not spam or luck.

## Core Rules

- Projectile travel is always visible (no hitscan).
- Broadside alignment gates firing quality.
- Misses are understandable (distance, motion, angle).
- Stable, well-aligned broadsides at optimal range are reliable.

## Cannon elevation (quoin)

- **Barrel elevation** is continuous from **−3°** (max depression) to **+5°** (max elevation) relative to the horizontal plane, exposed on `BatteryController` as normalized `cannon_elevation` (0 → −3°, 1 → +5°). **0° bore** corresponds to normalized **≈ 0.375** (`CANNON_ELEVATION_ZERO_DEG`, linear map between the two limits).
- **Ballistics:** `CannonBallistics.initial_velocity(..., elevation_deg)` uses **`cos(elevation)` / `sin(elevation)`** to split muzzle speed into horizontal **(wx, wy)** and vertical **(vz)** components so the quoin angle matches the simulated launch vector. The arena then applies a uniform scale to match target horizontal speed (`naval_combat_constants.gd` / ship tuning). A separate “vz-only” multiplier is **not** used once elevation is applied this way.
- UI / key bindings adjust `cannon_elevation` over time (`adjust_elevation`); see `req-battery-fsm.md` for fields.

## Projectile Model

- Speed: design target **~55 world units/sec** horizontal; **implementation** may use a higher baseline (e.g. **~110 u/s**) after mass and map-scale tuning — check `NC.PROJECTILE_SPEED` and `_fire_projectile` scaling.
- Lifetime: target default **4.5s**; implementation may differ (e.g. **6s**) for range envelope — see `NC.PROJECTILE_LIFETIME`.
- Max distance: roughly 300-450 units depending on elevation and tuning.
- Gravity: light arc (`CannonBallistics.GRAVITY` + `PROJECTILE_GRAVITY_SCALE`).

## Accuracy Model

- No damage falloff; hit = full effect, miss = zero.
- Deterministic spread cone by distance:
  - <100u: +/-2-4 deg
  - 100-200u: +/-5-8 deg
  - max range: +/-10-15 deg
- Movement penalties:
  - shooter turning: +30-50% spread
  - shooter high speed: +25% spread

## Fire Modes

- Keep both Salvo and Ripple.
- Default cannons per side: 8 (acceptable range 6-12).
- Ripple interval: 0.3s.
- Full ripple duration: 2-4s.
- Fire is committed once sequence starts.

## Feedback Requirements

- Muzzle flash (0.1-0.2s).
- Muzzle smoke (1-3s).
- Cannonball trail.
- Water splash on miss (1-2s).
- Hull impact burst on hit.
- Audio: cannon boom, impact cue, optional near-miss whiz.

## Timing Targets

- Reload: target default **18s**.
- Projectile travel: 1-2.5s typical.
- Turn-to-align: 5-10s.
- Screen cross: ~15s.
- Engagement duration: 25-40s.
- Reaction window: 3-5s.

