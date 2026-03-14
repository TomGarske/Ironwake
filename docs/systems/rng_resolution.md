# RNG Resolution System

**References:** [Game Philosophy](../design/game_philosophy.md) · [Combat System](combat_system.md)

---

## Overview

The RNG resolution system is the probability engine underlying every contested action in BurnBridgers. It translates a single effective probability value into one of four tiered outcomes. The system is inspired by tabletop RPG resolution mechanics (Powered by the Apocalypse, Blades in the Dark) but is adapted for a digital tactical context where precise probability control and network determinism are requirements.

The system is designed around the core philosophy: **skill and positioning determine probability; probability determines tier distribution; tiers determine what actually happens.** The RNG roll is the last step, not the first.

---

## Design Goals

- **Enforce the 25–75% probability band.** No meaningful action should have an effective probability outside this range after all modifiers. Actions outside this band feel either inevitable or pointless, removing player agency.
- **Eliminate binary miss/hit.** Every roll produces a named outcome with gameplay consequences. Players are never left with "nothing happened."
- **Weight toward the middle tiers.** At baseline probability, roughly two-thirds of outcomes should be positive (Complete Success or Success with Drawback). This is the two-thirds fairness principle from the game philosophy.
- **Be completely deterministic given a seed.** The same action with the same effective probability and the same RNG seed must always produce the same outcome, ensuring host-authoritative multiplayer correctness.
- **Be inspectable before commitment.** The probability tier distribution for any pending action must be computable without side effects, so the UI can display it.

---

## Core Mechanics

### The Four Outcome Tiers

| Tier | Code | Meaning |
|------|------|---------|
| 4 — Complete Success | `COMPLETE_SUCCESS` | Full intended effect. Best case. |
| 3 — Success with Drawback | `SUCCESS_DRAWBACK` | Effect succeeds, but at a cost. |
| 2 — Failure | `FAILURE` | No effect. Neutral or minor setback. |
| 1 — Critical Failure | `CRITICAL_FAILURE` | No effect. Significant negative consequence. |

Tiers 3 and 4 are collectively "successes." Tiers 1 and 2 are collectively "failures."

### Probability-to-Tier Mapping

The effective probability `p` (a float in [0.0, 1.0]) determines the width of each tier band. The mapping is:

```
Tier 4 (Complete Success):   p * 0.50               → top 50% of successes
Tier 3 (Success/Drawback):   p * 0.50               → bottom 50% of successes
Tier 2 (Failure):            (1.0 - p) * 0.67       → top 67% of failures
Tier 1 (Critical Failure):   (1.0 - p) * 0.33       → bottom 33% of failures
```

Expressed as cumulative thresholds for a uniform roll `r` in [0.0, 1.0):

```
if r < p * 0.50:               → Tier 4 (Complete Success)
elif r < p:                    → Tier 3 (Success with Drawback)
elif r < p + (1.0-p) * 0.67:  → Tier 2 (Failure)
else:                          → Tier 1 (Critical Failure)
```

### Baseline Distribution at p = 0.50

At the midpoint of the probability band:

| Tier | Probability |
|------|------------|
| Complete Success | 25% |
| Success with Drawback | 25% |
| Failure | 33% |
| Critical Failure | 17% |

Combined success rate: **50%** (matching `p`).

### Baseline Distribution at p = 0.65 (two-thirds principle)

At the recommended "fair fight" baseline — the two-thirds fairness value:

| Tier | Probability |
|------|------------|
| Complete Success | 32.5% |
| Success with Drawback | 32.5% |
| Failure | 23.5% |
| Critical Failure | 11.5% |

Combined success rate: **65%**, consistent with the two-thirds fairness principle.

### Probability Band Enforcement

The effective probability is clamped before the roll:

```gdscript
effective_p = clampf(effective_p, 0.25, 0.75)
```

This ensures:
- Even in the worst conditions, a 25% success rate remains — the player always has a chance.
- Even in the best conditions, a 25% failure rate remains — perfect safety never exists.

### Seeded Randomness

All rolls use `RandomNumberGenerator` with an explicit seed. The host manages the RNG state. Each action consumes one RNG step. The host transmits the outcome tier (not the raw roll) to clients, so clients never need to replicate the RNG state.

For the offline test mode, a fixed seed may be set at match start for reproducibility during development.

```gdscript
var _rng := RandomNumberGenerator.new()

func resolve(effective_p: float) -> int:
    effective_p = clampf(effective_p, 0.25, 0.75)
    var r := _rng.randf()  # uniform [0.0, 1.0)
    if r < effective_p * 0.50:
        return OutcomeTier.COMPLETE_SUCCESS
    elif r < effective_p:
        return OutcomeTier.SUCCESS_DRAWBACK
    elif r < effective_p + (1.0 - effective_p) * 0.67:
        return OutcomeTier.FAILURE
    else:
        return OutcomeTier.CRITICAL_FAILURE
```

---

## Data Structures

### OutcomeTier Enum

```gdscript
enum OutcomeTier {
    CRITICAL_FAILURE = 1,
    FAILURE          = 2,
    SUCCESS_DRAWBACK = 3,
    COMPLETE_SUCCESS = 4,
}
```

### TierDistribution (UI / pre-action preview)

```gdscript
# Pure computation — no RNG consumed
func get_tier_distribution(effective_p: float) -> Dictionary:
    effective_p = clampf(effective_p, 0.25, 0.75)
    return {
        OutcomeTier.COMPLETE_SUCCESS: effective_p * 0.50,
        OutcomeTier.SUCCESS_DRAWBACK: effective_p * 0.50,
        OutcomeTier.FAILURE:          (1.0 - effective_p) * 0.67,
        OutcomeTier.CRITICAL_FAILURE: (1.0 - effective_p) * 0.33,
    }
```

### Resolution Event (replicated from host)

```gdscript
{
    action_id:     int,     # Unique ID for this resolution event
    outcome_tier:  int,     # OutcomeTier value
    effective_p:   float,   # The clamped probability used (for replay / logging)
}
```

---

## Implementation Notes

- The `resolve()` function must live on an autoload or a class that is only called on the host. Clients receive the `outcome_tier` via RPC, not the raw roll.
- `get_tier_distribution()` is a pure function and is safe to call on any peer for UI display.
- During the POC phase, the resolution is simplified to a single success/failure split at `effective_p`. The full four-tier system is the first post-POC combat feature.
- The RNG object (`_rng`) should be initialized with a lobby-derived seed that both peers agree on at match start, ensuring any future replay or deterministic testing features can reconstruct the exact sequence.
- Logging every resolution event (action_id, effective_p, outcome_tier) to a match history array enables post-match analysis and will support a future "replay" feature.

---

## Future Extensions

- **Modified tier ratios**: specific abilities or unit traits might shift the 50/50 split between Complete Success and Success with Drawback without changing the total success probability.
- **Streak protection**: if a player has suffered N consecutive Critical Failures, suppress the Critical Failure tier for the next roll.
- **Seeded replay**: store the match seed and action sequence to enable full match replay.
- **Visual probability display**: show the four tier bands as a color-coded bar in the action confirmation UI.
- **Ability-specific tier effects**: tie the secondary_effect field of the combat result to the tier, allowing abilities to define custom consequences for each outcome tier.
