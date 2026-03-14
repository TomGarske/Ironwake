# BurnBridgers — Game Design Philosophy

## Purpose

This document establishes the foundational design principles for BurnBridgers. It serves as the authoritative reference for all gameplay, system, and balance decisions made during development. When a mechanic, rule, or system is in question, this document should be consulted first.

All system specifications in `/docs/systems` and all Architecture Decision Records in `/docs/adr` should align with the principles described here. Exceptions must be recorded as a new ADR that explicitly acknowledges and justifies the deviation.

---

## Core Philosophy

### 1. Player Agency Over Randomness

BurnBridgers is a tactical game. The player's primary satisfaction comes from making smart decisions under pressure — not from being lucky.

Randomness exists in the game to create tension and variety, not to determine winners. A player who positions their squad well, exploits terrain, and times their actions correctly should succeed more often than a player who does not, regardless of dice outcomes.

**Randomness serves agency. Agency does not serve randomness.**

This means:

- Randomness should never override a clearly correct tactical decision.
- Players should always be able to read the probability of an outcome before committing to an action.
- High-variance outcomes (e.g., lucky crits, catastrophic failures) should feel meaningful in the context of the game state, not arbitrary.
- Every random outcome should still leave the player with a decision to make.

---

### 2. The 25–75 Probability Band

Probability systems in BurnBridgers operate within a **25–75% success range** for most actions under normal conditions.

This range is intentional. Outcomes outside this band erode player agency:

- Below 25%: Players feel they are gambling, not deciding. Success becomes a lottery.
- Above 75%: Players feel the action is automatic. Failure feels unfair and punishing.

The 25–75 band is the zone where both success and failure feel earned. Players can weigh risk against reward meaningfully, and neither outcome feels like a betrayal of their decision.

**Design implication:** Base success rates for core actions (attacks, abilities, support actions) should be tuned to land within this band under normal engagement conditions. Modifiers — terrain, flanking, squad buffs, status effects — shift values within and across this range, giving skilled play a tangible advantage without making outcomes feel predetermined.

---

### 3. The Two-Thirds Fairness Principle

Within the 25–75 band, player perception of fairness peaks at approximately **two-thirds probability (~67%)**.

This is a well-documented pattern in game design: when players succeed roughly two times out of three, they experience the system as fair and rewarding. When they fail more often than they succeed, systems feel punishing. When they almost never fail, systems feel meaningless.

**Design implication:** The default success rate for a well-positioned, competent tactical action — a standard attack on an undefended target at optimal range — should sit near **65–70%**. Modifiers then move outcomes up or down within the probability band. Players playing well should regularly sit above 67%. Players playing poorly or taking unnecessary risks should fall below it.

---

### 4. Tiered Outcome Resolution

BurnBridgers does not use binary pass/fail resolution. Every action that involves uncertainty resolves into one of four outcome tiers:

| Tier | Name | Description |
|------|------|-------------|
| **4** | Complete Success | The action succeeds fully. The intended effect occurs with no drawback. |
| **3** | Success with Drawback | The action succeeds, but at a cost. The goal is achieved with a complication, positioning penalty, resource drain, or secondary consequence. |
| **2** | Failure | The action fails. The intended effect does not occur. The game state is unchanged or worsened. |
| **1** | Critical Failure | The action fails with an additional negative consequence — exposure, collateral effect, or loss of follow-up options. |

**Why this matters:** Binary outcomes create frustrating swings. A missed shot ends a player's turn with nothing to show. A tiered system ensures that even failed actions move the game state forward in some way. A "Success with Drawback" creates a new problem to solve. A "Critical Failure" raises the stakes without removing player agency entirely.

Tiered resolution also encourages meaningful risk evaluation. Players weigh not just "will this succeed?" but "what is the cost if it only partially succeeds?" This is richer decision-making.

**Probability mapping across tiers** (baseline — unmodified action at standard range):

| Tier | Target Probability |
|------|--------------------|
| Complete Success | ~35% |
| Success with Drawback | ~35% |
| Failure | ~20% |
| Critical Failure | ~10% |

Modifiers shift the entire distribution upward or downward. A well-buffed, well-positioned action raises the Complete Success share and compresses Failure and Critical Failure. A desperate action under suppression shifts weight toward the lower tiers.

See [`/docs/systems/rng_resolution.md`](../systems/rng_resolution.md) for the technical implementation of this system.

---

## Influence on System Design

These four principles should actively shape every system built in BurnBridgers:

### Combat
Grid-based tactical combat should reward positional intelligence. Cover, flanking, elevation, and range should all produce meaningful probability shifts within the 25–75 band. A player who maneuvers well should expect to operate near the top of the band; an exposed unit pressing a defended position should expect the bottom. See [`/docs/systems/combat_system.md`](../systems/combat_system.md).

### Turn Structure
The turn system must be deterministic and transparent. Players need to know what will happen and when. Surprise mechanics should be earned through tactical play (ambush positioning, preparation actions) rather than injected through random event systems. See [`/docs/systems/turn_system.md`](../systems/turn_system.md).

### Squad Composition
Squads should be small enough that every unit's survival is meaningful, and composition decisions should be strategic, not optimized. No single unit should be so dominant that the squad composition decision is obvious. See [`/docs/systems/squad_system.md`](../systems/squad_system.md).

### Networking
The multiplayer system must ensure that both players experience the same game state. Randomness must be resolved authoritatively on the host and replicated deterministically. No client should ever see a different probability outcome than their opponent. See [`/docs/systems/networking_model.md`](../systems/networking_model.md).

---

## Evolving This Document

This document is a living reference, not a locked specification. As development progresses and playtesting reveals problems or opportunities, the principles here may need to evolve.

Any change to this document must be reviewed in the context of existing system specifications and ADRs. If a change conflicts with a recorded ADR, a new ADR must be created explaining the revision and its rationale.

Changes should not be made to align the philosophy with a mechanic that was implemented for convenience. Instead, mechanics should be evaluated against this document and updated or removed if they contradict it.
