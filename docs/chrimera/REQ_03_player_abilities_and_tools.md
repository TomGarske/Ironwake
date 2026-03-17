# REQ-03: Player Abilities and Tools
**Chrimera: Bioforge Run**

## Overview
The scientist player character has **base actions** (movement, interaction) and **two active tool slots** that are populated by **Experimental Tools** discovered during a run. Tools are never pre-selected; discovery is forced and creates playstyle diversity. This document defines base actions, tool categories, individual tool mechanics, and cooperative synergies.

---

## Base Actions

### Movement Actions
| Action | Input | Behavior | Notes |
|--------|-------|----------|-------|
| **Move Left/Right** | Left Stick (analog) | Character accelerates/decelerates in direction. Max speed ~8 m/s. | Physics-driven via CharacterBody2D.velocity. |
| **Jump** | A (or Space) | Variable-height jump. Holding A extends jump height (gravity reduction). Max height ~4 tiles (~2m). | Coyote time: 0.1s after leaving ground. Jump buffer: 0.15s. |
| **Crouch/Slide** | B | Reduces hitbox height (50% of normal). Slide provides brief speed boost and i-frames (0.2s). | Cooldown 1s between slides to prevent abuse. |
| **Wall-Grab** (Optional) | Pressing toward wall while airborne | Character clings to vertical surfaces. Stamina drain ~20/s. Can jump off or slide down. | Deferred feature (not MVP). |

### Interaction Actions
| Action | Input | Behavior | Notes |
|--------|-------|----------|-------|
| **Interact/Pickup** | Y | Pick up tools, open locked doors (with keycard), revive downed teammates. Interaction range 1m. | Triggers nearest interactive object. |
| **Melee** | X | Desperation-only close-range attack. 3-tile range, 5 damage, 0.5s cooldown. Interrupts movement during swing. | High risk; reserved for trapped scenarios. |
| **Tool Use (Slot 1)** | RT | Use active tool in slot 1. Behavior varies per tool (immediate effect, projectile, area, buff). | Respects tool's cooldown/consumable state. |
| **Tool Use (Slot 2)** | LT | Use active tool in slot 2. Behavior varies per tool. | Respects tool's cooldown/consumable state. |

---

## Tool System

### Tool Slots and Swapping

```gdscript
class ToolSlotManager:
    var slot_1: ExperimentalTool
    var slot_2: ExperimentalTool
    var max_slots: int = 2  # upgradeable to 3 via meta-progression

    func pickup_tool(tool: ExperimentalTool):
        if slot_1 == null:
            slot_1 = tool
            tool_slot_updated.emit(1, tool)
        elif slot_2 == null:
            slot_2 = tool
            tool_slot_updated.emit(2, tool)
        else:
            # Both slots full; player must choose: drop one or discard new
            prompt_swap_tool(tool)

    func swap_tool(slot: int, new_tool: ExperimentalTool):
        var old_tool = [slot_1, slot_2][slot - 1]
        [slot_1, slot_2][slot - 1] = new_tool
        tool_slot_updated.emit(slot, new_tool)
        # Old tool remains in level as pickup (respawns at pickup location)
```

### ExperimentalTool Base Class

```gdscript
class_name ExperimentalTool
extends Resource

@export var tool_name: String
@export var description: String
@export var tool_type: Enum  # MOBILITY, OFFENSIVE, DEFENSIVE, UTILITY
@export var rarity: Enum  # COMMON, UNCOMMON, RARE, ELITE
@export var icon: Texture2D

# Behavior
@export var is_consumable: bool = false  # true = single-use, false = cooldown-based
@export var cooldown_seconds: float = 5.0
@export var charges: int = 1  # if consumable

var current_cooldown: float = 0.0

signal tool_used()
signal cooldown_started(duration: float)
signal ready()

func use(player: PlayerCharacter) -> bool:
    """Returns true if tool was successfully used."""
    if current_cooldown > 0.0:
        return false

    execute_effect(player)
    tool_used.emit()

    if is_consumable:
        charges -= 1
        if charges <= 0:
            player.tool_slot_manager.remove_tool(self)
    else:
        current_cooldown = cooldown_seconds
        cooldown_started.emit(cooldown_seconds)

    return true

func execute_effect(player: PlayerCharacter):
    """Override in subclasses."""
    pass

func _process(delta: float):
    if current_cooldown > 0.0:
        current_cooldown -= delta
        if current_cooldown <= 0.0:
            ready.emit()
```

---

## Tool Categories and Library

### MOBILITY Tools
#### 1. Grapple Spike
- **Description:** Launches a magnetic spike on a 3m cable. Pulls player toward anchor point or pulls small objects.
- **Use:** Swings across gaps, reaches elevated platforms, retrieves items from distance.
- **Mechanic:** Click to fire, hold to retract. Grapple point must be valid (marked geometry or enemy).
- **Cooldown:** 2s
- **Synergy:** None (single-player utility).
- **Rarity:** Uncommon

#### 2. Speed Serum
- **Description:** Biochemical stimulant injection. Grants 1.5x movement speed and reduced friction for 8s.
- **Use:** Escape threat encounters, rush to exit before contamination spreads.
- **Mechanic:** Instant-cast buff. Stamina drain removed during effect. Stamina recovers slower after (fatigue penalty).
- **Cooldown:** 20s
- **Synergy:** Pairs with Barrier Foam; invulnerability + speed allows aggressive positioning.
- **Rarity:** Common

#### 3. Lateral Thruster
- **Description:** Compact jet pack for quick horizontal dashes (8m distance, 0.3s duration).
- **Use:** Dodge entity attacks, cross hazard zones, platform skip.
- **Mechanic:** Tap directional input twice or hold RT + direction. Three charges per cooldown.
- **Cooldown:** 12s (regenerates 1 charge per 4s, max 3).
- **Synergy:** Offensive synergy with EMP Grenade; dash + grenade = crowd control + damage.
- **Rarity:** Uncommon

---

### OFFENSIVE Tools
#### 1. Acidic Compound
- **Description:** Vial of corrosive bioacid. Throws in arc; explodes on impact, dealing 20 damage in 3m radius and corroding armor (applies -5 defense debuff for 6s).
- **Use:** Weaken high-armor entities (Amalgams), area clear, trigger escalations (danger = risk).
- **Mechanic:** Aim and throw (slow arc projectile, 2s flight time). Consumable (single use).
- **Synergy:** Combo with melee or teammate attacks during debuff window for bonus damage.
- **Rarity:** Uncommon

#### 2. EMP Grenade
- **Description:** Electromagnetic pulse bomb. Explodes on contact; disables entity attacks for 3s (stun-like effect) and temporarily disables all electronics in facility (turrets, locked doors).
- **Use:** Crowd control, escape, open electronic barriers.
- **Mechanic:** Throw or detonate on proximity. Consumable (1 charge).
- **Synergy:** Pairs with Lateral Thruster dash; dash in, grenade, allies attack stunned enemies.
- **Rarity:** Rare

#### 3. Sonic Emitter
- **Description:** Sonic projector. Emits 2s directional pulse (120° cone, 5m range). Damages and knockbacks all entities in cone. Crawlers take double damage.
- **Use:** Group clear, knockback threats away from exit, channel-based active defense.
- **Mechanic:** Hold RT to activate; point direction; releases pulse at end. Visual/audio feedback (loud beep).
- **Cooldown:** 8s
- **Synergy:** No direct synergy; standalone area denial tool.
- **Rarity:** Uncommon

#### 4. Toxin Injector (Rare Elite Tool)
- **Description:** Advanced biohazard syringe. Fires poison dart (fast projectile); on hit, poisons target, dealing 5 damage/s for 12s. Affected entities move 30% slower.
- **Use:** Single-target DoT sustained damage, slowing high-threat entities.
- **Mechanic:** Click to fire. Multiple darts in quick succession (3 charges, each with 1s cooldown).
- **Cooldown:** 15s
- **Synergy:** Poison + Stasis Gel; slowed entity becomes easier to manage with immobilization.
- **Rarity:** Elite

---

### DEFENSIVE Tools
#### 1. Barrier Foam
- **Description:** Pressurized foam expands on ground, creating temporary wall (2m height, 4m width, 6s duration) that blocks movement and projectiles.
- **Use:** Block exits temporarily (trap entity in room), create safe zone, protect downed teammate.
- **Mechanic:** Place at cursor location (range 6m). Foam decomposes after duration or on strong impact (e.g., Amalgam charge).
- **Cooldown:** 10s
- **Synergy:** Speed Serum + Barrier Foam; invulnerability + defensive wall = hold chokepoint indefinitely.
- **Rarity:** Common

#### 2. Stasis Gel
- **Description:** Temporal suspension compound. Sprays area (2m radius, centered at cursor). All entities in radius are frozen for 5s (cannot move or attack).
- **Use:** Immobilize threats, buy time for revives, delay escalations.
- **Mechanic:** Instant-cast. Friendly fire on teammates possible (they freeze too); must communicate.
- **Cooldown:** 14s
- **Synergy:** Frozen enemy + Sonic Emitter = guaranteed KO; frozen enemy + teammate melee = bonus damage multiplier (2x).
- **Rarity:** Uncommon

#### 3. Med-Kit (Consumable)
- **Description:** Field medical supplies. Single use; restores 30 HP to self or reviving teammate (+25 HP to revived target).
- **Use:** Emergency healing, extend survival.
- **Mechanic:** Use on self or ally within 3m. Consumable (single charge).
- **Rarity:** Common

---

### UTILITY Tools
#### 1. Scanner
- **Description:** Biometric scanner device. Reveals all entities on current level on minimap for 8s. Shows entity type, health bar, location.
- **Use:** Strategic planning, ambush prediction, find exit.
- **Mechanic:** Activate (instant-cast, passive). Duration 8s, then requires recharge.
- **Cooldown:** 15s
- **Synergy:** No direct synergy; information is the value.
- **Rarity:** Common

#### 2. Keycard Cracker
- **Description:** Electronic lock override device. Hacks keycards and electronic doors. One use per door.
- **Use:** Open locked passages, shortcut around threats, reach hidden tool caches.
- **Mechanic:** Approach locked door/keycard, press Y to use. 3s hacking animation. Consumable per lock (infinite uses across different locks).
- **Cooldown:** None
- **Rarity:** Common

#### 3. Stabilization Serum
- **Description:** Prevents downed state for 15s after first fatal damage. On expiration, player is downed (revivable normally).
- **Use:** Insurance against instant death, solo survivability.
- **Mechanic:** Automatic passive buff when active. Buff expires after one "save" or 15s, whichever is first.
- **Cooldown:** 20s
- **Rarity:** Uncommon

#### 4. Contamination Filter (Rare)
- **Description:** Adaptive bio-filter mask. Reduces contamination zone damage by 60%. Extends duration in hazardous areas.
- **Use:** Navigate through heavy contamination zones that block other paths.
- **Mechanic:** Passive buff while equipped. Duration: until level exit.
- **Rarity:** Rare

---

## Melee (Base Action)

### Desperation Attack
- **Range:** 3 tiles (roughly 1.5m)
- **Damage:** 5 HP
- **Cooldown:** 0.5s between strikes
- **Duration:** 0.3s swing animation (movement locked)
- **Use Case:** Cornered, no tools available, entity in close quarters.
- **Risk:** Leaves player vulnerable; low damage output makes it inefficient against groups.

---

## Cooperative Synergies

### Tool Pairing Table

| Tool A | Tool B | Synergy | Bonus |
|--------|--------|---------|-------|
| Speed Serum | Barrier Foam | Invulnerable speed hold | +1.5x Serum duration when wall active |
| Lateral Thruster | EMP Grenade | Dash-in crowd control | +50% grenade radius on dash-used grenade |
| Stasis Gel | Sonic Emitter | Frozen enemies amplify damage | +2x Emitter damage on frozen targets |
| Acidic Compound | Melee | Debuffed target weaker | Melee does 10 damage (not 5) on corroded targets |
| Grapple Spike | Any | Mobility pairs with any exit rush | N/A (utility synergy) |

### Teammate Proximity Bonuses
- **Within 3m of ally:** Movement speed +10%, tool cooldowns -10%.
- **Reviving downed ally:** Using Med-Kit heals revived ally +50% (25 HP → 37 HP).
- **Synchronized tool use:** If two players use Stasis Gel simultaneously on same target, stun duration extends to 8s.

---

## Tool Rarity and Spawn

| Rarity | Spawn Rate | Availability | Notes |
|--------|-----------|---------------|-------|
| **Common** | 50% of pickups | Speed Serum, Barrier Foam, Scanner, Keycard Cracker, Med-Kit | Starting tool pool. |
| **Uncommon** | 35% of pickups | Grapple Spike, Sonic Emitter, Lateral Thruster, Acidic Compound, Stasis Gel, Stabilization Serum | Unlocked early after first 3 runs. |
| **Rare** | 12% of pickups | EMP Grenade, Contamination Filter | Unlocked after 5+ run completions. |
| **Elite** | 3% of pickups | Toxin Injector | Unlocked after defeating Chimera Host or 10+ runs. |

---

## Implementation Notes

1. **Tool Discovery:** Tools spawn in ToolPickup instances scattered throughout levels. No player starts with tools in inventory; first pickup of level establishes slot 1.
2. **Cooldown Display:** HUD shows remaining cooldown as a radial progress indicator on tool icon. Consumable tools show charge count.
3. **Friendly Fire:** Stasis Gel affects all entities (including teammates). Scanner reveals all, not just enemies. Use team communication.
4. **Tool Persistence:** If a player dies while holding a tool, the tool remains on the ground at death location (accessible to surviving teammates).
5. **Vendetta Against Tool Loss:** Tools left behind at level exit are lost (not carried to next level). This forces renegotiation of loadout each level.
6. **Multiplayer Tool Sync:** In multiplayer, each player's tool slots are independently managed. No "shared tool pool" across players; each pickup is a unique instance.

---

## Next Steps
- **REQ-04:** Player movement and controls (input bindings, physics parameters, camera behavior).
- **REQ-05:** Roguelike progression (meta-upgrades, archetype unlocks).
