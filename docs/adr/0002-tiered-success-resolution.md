# ADR 0002: Tiered Success Resolution

**Status:** Accepted  
**Date:** 2025  
**References:** [Game Philosophy](../design/game_philosophy.md) · [RNG Resolution](../systems/rng_resolution.md) · [Combat System](../systems/combat_system.md)

---

## Context

BurnBridgers requires a resolution mechanic for contested actions (attacks, abilities). Any resolution system must:

- Produce outcomes that feel fair and legible to both players
- Reward tactical positioning without making careful play feel guaranteed
- Avoid "wasted turns" where a player simply does nothing because they failed a roll
- Integrate with the host-authoritative network model (see ADR 0001)
- Be inspectable: the player should be able to see probability information before committing to an action

The conventional binary hit/miss system used in most tactical games was the default starting point. Two alternatives were considered:

1. **Binary hit/miss**: roll above threshold → full damage, roll below → no effect. Simple and familiar. Problem: a missed attack produces no gameplay consequence, and runs of misses feel arbitrary and frustrating. High-variance outcomes undermine player agency.
2. **Degree-of-success (tabletop-style)**: the roll result produces a spectrum of outcomes — not just hit or miss, but how well the action succeeded or how badly it failed. Used in Powered by the Apocalypse and Blades in the Dark. Each outcome tier has distinct mechanical meaning. Problem: historically difficult to implement in digital games because the outcome mapping must be clearly communicated to the player.
3. **Fixed probability with variable effects**: a roll always "hits" but the magnitude varies (e.g., 1–3 damage on a 1d6). Problem: variable damage introduces compounding randomness and makes probability displays harder to interpret. Outcome ranges are less legible than named tiers.

The game's [design philosophy](../design/game_philosophy.md) explicitly rejects binary outcomes and mandates a tiered success system. The probability band (25–75%) and the two-thirds fairness principle are core to the design intent.

---

## Decision

**Implement a four-tier outcome system: Critical Failure, Failure, Success with Drawback, Complete Success.**

All contested actions resolve against a single effective probability `p`, clamped to [0.25, 0.75]. The roll maps `p` to one of the four tiers using fixed band ratios (see [rng_resolution.md](../systems/rng_resolution.md) for exact formulas).

Key properties of the chosen system:
- Combined success rate equals `p` exactly (Success with Drawback + Complete Success = p)
- Successes are split 50/50 between Complete Success and Success with Drawback
- Failures are split ~67/33 between Failure and Critical Failure
- At `p = 0.65` (the two-thirds fairness baseline), ~65% of outcomes are positive
- The 25–75% clamp ensures no action is ever a coin-flip below 25% or a near-certainty above 75%

All resolution occurs on the host. The host transmits the outcome tier (an integer) to clients, not the raw roll. This is consistent with the host-authoritative architecture and avoids floating-point divergence.

---

## Consequences

**Positive:**
- Every action produces a named, meaningful outcome. Failures still advance the game state (suppression, exposure, positioning implications).
- Probability transparency is achievable: `get_tier_distribution(p)` is a pure function that can power a pre-action UI display showing all four tier likelihoods.
- The system is inspectable and fair: players understand that they always have at least a 25% chance of success and always face at least a 25% chance of failure.
- The tabletop inspiration (PbtA, Blades in the Dark) provides a proven design precedent for this style of resolution.
- Outcome tiers are integers — trivially serializable and network-safe.

**Negative:**
- Four outcome tiers require four distinct gameplay consequences to be designed and implemented per action type. The POC simplifies this (tiers 3 and 4 both deal damage; tiers 1 and 2 do not), but full implementation requires meaningful secondary effects for all tiers of all action types.
- Players unfamiliar with tabletop RPG conventions may need onboarding to understand that "Success with Drawback" is not simply a miss.
- The 50/50 split between Complete Success and Success with Drawback is a fixed ratio in the current design. If playtesting reveals that the drawback tier is too common or too rare, adjusting it requires a change to the core resolution formula that affects all action types simultaneously.
- The probability band (25–75%) is a design constraint that limits how much modifiers can shift outcomes. High-difficulty actions cannot be made "nearly impossible" in the current system. This is intentional but requires that the modifier system be designed carefully to stay within the band.
