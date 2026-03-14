# Combat System

**References:** [Game Philosophy](../design/game_philosophy.md) · [RNG Resolution](rng_resolution.md) · [Turn System](turn_system.md)

---

## Overview

BurnBridgers uses a grid-based tactical combat system where two players control small squads of units on a tile map. Combat resolves through a tiered outcome system rather than binary hit/miss. Every attack, ability, and contested action produces a meaningful result regardless of the raw outcome — units never simply "do nothing."

The combat system is the primary vehicle for expressing the design philosophy. Positional intelligence — cover, flanking, range management, and squad coordination — should produce measurable probability advantages. Raw aggression against defended positions should feel risky, not reliable.

---

## Design Goals

- **Reward positioning** over raw stats. A unit in cover attacking a flanked enemy should have a substantially higher expected outcome than a unit attacking into cover from the open.
- **Keep squads small and fragile.** Each unit lost is meaningful. Combat should feel tense, not atritional.
- **Eliminate binary outcomes.** Every action resolves to a tiered result (see [rng_resolution.md](rng_resolution.md)). Failed attacks still inform the tactical picture — they may suppress, expose, or delay rather than simply miss.
- **Maintain synchronization.** All combat resolution occurs on the host and is broadcast to clients. No client-side prediction of random outcomes.
- **Transparency.** Before committing to an action, the player can see the probability tier distribution for that action.

---

## Core Mechanics

### Grid and Range

The map is a discrete tile grid. Each tile is either occupied or unoccupied. Units occupy exactly one tile at a time.

**Range categories:**

| Category | Distance (Manhattan) | Base Success Modifier |
|----------|---------------------|-----------------------|
| Melee | 1 | +15% |
| Close | 2–3 | +0% (baseline) |
| Medium | 4–6 | −10% |
| Long | 7+ | −20% |

Range modifiers stack with other modifiers and shift the tiered outcome distribution.

### Cover

Cover is a property of the defending unit's tile, not the attacker's. A unit in cover reduces the attacker's effective success probability.

| Cover Type | Modifier to Attacker |
|------------|----------------------|
| None | +0% |
| Partial Cover | −15% |
| Full Cover | −30% |

Cover is directional. A unit behind a wall is only in cover against attacks coming from the protected side. Flanking removes cover.

### Flanking

A unit is flanked when it is attacked from a tile that is not within its forward arc (the three tiles directly ahead and to either side). Flanking negates cover and adds a bonus to the attacker.

| Flank State | Modifier to Attacker |
|-------------|----------------------|
| Not Flanked | +0% |
| Flanked | +20%, cover negated |

Flanking requires coordination — the attacking player must position a second unit behind or beside the target during a prior action.

### Attack Resolution

An attack is resolved using the tiered outcome system described in [rng_resolution.md](rng_resolution.md). The attacking unit's effective probability is calculated as:

```
effective_probability = base_attack_probability
                      + range_modifier
                      + flank_modifier
                      - cover_modifier
                      + unit_buffs
                      - unit_debuffs
```

The result is clamped to a minimum of 10% and a maximum of 90% to preserve outcome uncertainty.

**Tiered attack outcomes:**

| Tier | Outcome |
|------|---------|
| Complete Success | Full damage dealt. Target may be pushed back one tile (attacker's choice). |
| Success with Drawback | Damage dealt. Attacker exposes themselves (loses cover bonus next turn) or uses an additional action point. |
| Failure | No damage. Target may react — move one tile or enter overwatch (future extension). |
| Critical Failure | No damage. Attacker loses remaining action points this turn. Nearby allied units may be suppressed. |

### Damage and Health

Units have an integer health pool. Damage values are fixed per weapon or ability type — the tiered outcome determines *whether* damage lands and *what else happens*, not the damage amount itself.

This is intentional: variable damage introduces a second layer of randomness that competes with tiered resolution. Fixed damage keeps the RNG system clean and readable.

**Baseline damage values (POC):**

| Attack Type | Damage |
|-------------|--------|
| Melee Strike | 1 |
| Ranged Shot | 1 |

These values will expand in future phases as unit roles and weapon types are developed.

### Unit Death and Removal

When a unit's health reaches 0, it is immediately removed from the game. There is no downed state in the POC. Future extensions may introduce a downed mechanic where units can be stabilized by an ally before the end of a turn.

---

## Data Structures

### Unit (GDScript)

```gdscript
# scripts/unit.gd
var unit_id: int          # Unique identifier across the match
var team: int             # 0 or 1
var grid_pos: Vector2i    # Current tile position
var health: int           # Current HP
var max_health: int       # Maximum HP
var move_range: int       # Max Manhattan distance per move action
var has_moved: bool       # True if move action used this turn
var has_attacked: bool    # True if attack action used this turn
```

### Attack Request (RPC payload)

```gdscript
# Sent from client to host via request_attack RPC
{
  attacker_id: int,   # unit_id of attacking unit
  target_id: int,     # unit_id of target unit
}
```

### Combat Result (future — replicated from host)

```gdscript
{
  attacker_id: int,
  target_id: int,
  outcome_tier: int,      # 1–4 (Critical Failure to Complete Success)
  damage_dealt: int,
  secondary_effect: String  # "exposed", "suppressed", "pushed", ""
}
```

---

## Implementation Notes

- All combat resolution executes in `_server_validate_attack()` in `scripts/tactical_map.gd`. Clients send `request_attack` RPCs; the host validates, resolves, and broadcasts `apply_attack` to all peers.
- The POC uses simplified resolution: attacks either deal 1 damage (success) or deal no damage (failure). Full tiered resolution is the next implementation milestone — see [rng_resolution.md](rng_resolution.md).
- Cover and flanking are planned for post-POC implementation. The probability modifier architecture should be built into the resolution function from the start so these modifiers can be added without restructuring.
- The `effective_probability` calculation should be a pure function with no side effects, making it easy to expose in the UI before a player commits to an action.

---

## Future Extensions

- **Cover tiles** on the TileMap with directional coverage flags.
- **Suppression** status: a unit that suffers a Failure outcome may enter suppression, reducing their action options next turn.
- **Overwatch**: a unit that ends its turn without attacking may declare overwatch, triggering an interrupt attack when an enemy enters its range.
- **Area attacks**: grenades or ability effects that hit a radius of tiles, each resolved as an individual attack.
- **Downed mechanic**: units at 0 HP enter a downed state for one turn and can be stabilized by an adjacent ally.
- **Weapon variety**: different weapons with different range categories, damage values, and base probabilities.
