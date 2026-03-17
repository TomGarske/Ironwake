# REQ-06: CRISPR Entity AI
**Chrimera: Bioforge Run**

## Overview
CRISPR entities are the primary threats in Chrimera. All AI is driven by **LimboAI behavior trees** (node-based decision system native to Godot). Each entity type has distinct role, stat profile, and behavior tree. All entity decisions are **server-authoritative** in multiplayer (host runs tree logic, clients receive position/action snapshots).

---

## Entity Types

### 1. Crawler
**Role:** Basic swarm threat. Low health, fast, low damage. Appears in groups.

| Stat | Value |
|------|-------|
| **Health** | 10 HP |
| **Speed** | 5 m/s |
| **Damage per hit** | 2 HP |
| **Attack cooldown** | 0.5s |
| **Detection range** | 6m |
| **Attack range** | 1m |
| **Knockback resist** | 0.3 (light knockback effect) |

**Behavior Tree Logic:**
```
Root
├─ Selector
│  ├─ Condition: Player detected in 6m?
│  │  └─ Chase and Attack Sequence
│  │     ├─ Move toward player
│  │     ├─ If in attack range (1m): attack (2 dmg, 0.5s cooldown)
│  │     └─ Loop
│  │
│  └─ Idle/Patrol Sequence
│     ├─ Wander within room (random points)
│     ├─ Delay 3–5s between moves
│     └─ Loop
```

**Spawn Pattern:** Crawlers spawn 2–4 at a time. Waves occur every 10–15s during Pressure phase. Total per level: 8–32 (depending on level and difficulty).

---

### 2. Lurker
**Role:** High-damage burst threat. Ambushes from walls/ceilings. Low health, low speed.

| Stat | Value |
|------|-------|
| **Health** | 15 HP |
| **Speed** | 3 m/s (slow, deliberate) |
| **Damage per hit** | 8 HP (high burst) |
| **Attack cooldown** | 2.0s |
| **Detection range** | 10m |
| **Attack range** | 2m |
| **Ambush prep time** | 1s (visible telegraph) |
| **Knockback resist** | 0.5 |

**Behavior Tree Logic:**
```
Root
├─ Selector
│  ├─ Condition: Player in 10m AND not in attack cooldown?
│  │  └─ Ambush Sequence
│  │     ├─ Move 1m closer (slow creep)
│  │     ├─ Telegraph animation (1s, visible glow/sound)
│  │     ├─ If player not moved far: Burst Attack (8 dmg)
│  │     ├─ Reset cooldown (2.0s)
│  │     └─ Return to Idle
│  │
│  └─ Idle/Hide Sequence
│     ├─ Stay in shadow (corner of room)
│     ├─ Eyes glow to signal presence (non-threatening)
│     └─ Loop
```

**Spawn Pattern:** 1 Lurker per room. Positioned in corners, on walls, or ceiling edge. Spawn once per level during Pressure phase.

---

### 3. Spreader
**Role:** Area-denial threat. Contaminates zones. Medium health, slow movement.

| Stat | Value |
|------|-------|
| **Health** | 25 HP |
| **Speed** | 2 m/s (slowest) |
| **Damage per hit** | 1 HP |
| **Attack cooldown** | 0.3s (persistent pressure) |
| **Detection range** | 8m |
| **Attack range** | 2m |
| **Contamination radius** | 3m |
| **Contamination damage/sec** | 1 HP/s |
| **Knockback resist** | 0.8 (heavy, hard to move) |

**Behavior Tree Logic:**
```
Root
├─ Selector
│  ├─ Condition: Player in 8m AND in contamination zone?
│  │  └─ Spread and Pressure Sequence
│  │     ├─ Spawn contamination zone at current position (3m radius)
│  │     │  └─ ContaminationZone persists for 20s after Spreader leaves
│  │     ├─ Slowly advance toward player
│  │     ├─ Attack if in range (1 dmg/hit, 0.3s cooldown)
│  │     └─ Continue spreading
│  │
│  ├─ Condition: Player NOT in 8m?
│  │  └─ Wander Spread Sequence
│  │     ├─ Move to random points in room
│  │     ├─ Leave contamination trail as it moves
│  │     └─ Loop
│  │
│  └─ Idle Sequence
│     ├─ Stationary; spawn contamination at feet
│     └─ Loop (virtually never happens; always spreading)
```

**Spawn Pattern:** 1 Spreader spawned during Crisis phase per level. Placement: center of room (maximize trail coverage).

**Contamination Zone Behavior:**
```gdscript
class ContaminationZone:
    var damage_per_second: float = 1.0
    var radius: float = 3.0
    var persistence_duration: float = 20.0  # after Spreader leaves
    var visual_shader_intensity: float = 0.3

    func _on_player_enter():
        # Deal damage, apply visual overlay
        pass

    func _on_player_exit():
        # Stop damage, fade overlay
        pass
```

---

### 4. Amalgam
**Role:** Tank threat. Large, slow, high health. Blocks corridors and forces detours.

| Stat | Value |
|------|-------|
| **Health** | 60 HP |
| **Speed** | 1.5 m/s (slowest) |
| **Damage per hit** | 5 HP |
| **Attack cooldown** | 1.0s |
| **Detection range** | 8m |
| **Attack range** | 1.5m |
| **Size** | 2m wide, 2.5m tall (fills corridors) |
| **Knockback resist** | 1.0 (immune to knockback) |
| **Armor** | -3 incoming damage (min 1 per hit) |

**Behavior Tree Logic:**
```
Root
├─ Selector
│  ├─ Condition: Player in 8m?
│  │  └─ Slow Pursuit Sequence
│  │     ├─ Move toward player (methodical, no pathing)
│  │     ├─ If in attack range: attack (5 dmg, 1.0s cooldown)
│  │     ├─ Ignore diversions (tools don't slow it)
│  │     └─ Continue until player escapes line-of-sight
│  │
│  └─ Idle Sequence
│     ├─ Stationary; occasional animation twitch
│     └─ Wait
```

**Spawn Pattern:** 1 Amalgam per level during Crisis phase. Positioned in wide corridor (chokes traffic). Rarely downed by normal weapons; requires sustained assault or tool combo.

---

### 5. Chimera Host (Elite, Rare)
**Role:** Elite threat. Was a scientist before outbreak. Unpredictable, intelligent behavior. High loot drop.

| Stat | Value |
|------|-------|
| **Health** | 40 HP |
| **Speed** | 6 m/s (fast, erratic) |
| **Damage per hit** | 6 HP |
| **Attack cooldown** | 0.8s |
| **Detection range** | 12m |
| **Attack range** | 1.5m |
| **Abilities** | Teleport (blink), Projectile vomit, Grab (1-second pin) |
| **Knockback resist** | 0.6 |
| **Loot drop** | 1 Rare tool, 50 points, unlock "Chimera Host" archetype in meta-progression |

**Behavior Tree Logic:**
```
Root
├─ Selector
│  ├─ Condition: Health < 20 HP?
│  │  └─ Desperate Escape Sequence
│  │     ├─ Blink away from all players
│  │     ├─ Attempt to flee toward level exit
│  │     ├─ If cornered: All-Out Attack (2x damage, 2x attack speed for 5s)
│  │     └─ Blink again if possible
│  │
│  ├─ Condition: 2+ players nearby (within 5m)?
│  │  └─ Tactical Engage Sequence
│  │     ├─ Blink to a player's side
│  │     ├─ Use Projectile Vomit (arc projectile, 2m range, 4 dmg)
│  │     ├─ Attack nearest player
│  │     ├─ If attacked heavily: blink to other player
│  │     └─ Alternate targets
│  │
│  ├─ Condition: Single player OR any player in 8m?
│  │  └─ Hunting Sequence
│  │     ├─ Chase with variable speed (erratic)
│  │     ├─ Attack immediately on approach
│  │     ├─ Use Grab if player in 1.5m (pin for 1s, 6 dmg)
│  │     └─ Continue relentlessly
│  │
│  └─ Idle Sequence
│     ├─ Animated twitch, vocalizations
│     ├─ Eyes scan room (searching)
│     └─ Wait
```

**Special Abilities:**
- **Teleport Blink:** Instant move up to 5m away. Range unlimited but must see target location (no walls). Cooldown 3s.
- **Projectile Vomit:** Arc projectile (like Acidic Compound but faster). 2m range, 4 damage. Cooldown 2s.
- **Grab:** Pin player in place for 1s, deal 6 damage at end. Range 1.5m. Cooldown 4s.

**Spawn Pattern:** 1 Chimera Host spawns at Crisis phase (level 3+). Positioned at a major choke point or level exit region (forces confrontation). Killing it grants special meta-progression unlock and a Rare-tier tool drop.

---

## Multiplayer Server-Authoritative AI

In cooperative multiplayer:

```gdscript
# On host (server)
class CRISPREntity:
    extends CharacterBody2D

    var behavior_tree: LimboAI.BehaviorTree
    var is_server: bool = Engine.is_server()

    func _physics_process(delta: float):
        if is_server:
            # Host runs full behavior tree logic
            behavior_tree.tick()
            execute_decision()
            move_and_slide()  # apply physics

            # Broadcast state to clients every 0.1s
            broadcast_entity_snapshot()

# On client
    func _on_entity_snapshot_received(snapshot: Dictionary):
        # Apply server decision: position, animation, attack state
        global_position = snapshot.position
        velocity = snapshot.velocity
        animation_player.play(snapshot.animation)
```

### Snapshot Broadcast
Every 0.1s, the host sends:
```gdscript
var snapshot = {
    "entity_id": entity.entity_id,
    "position": entity.global_position,
    "velocity": entity.velocity,
    "animation": entity.current_animation,
    "health": entity.health,
    "attack_state": entity.is_attacking,
}
broadcast_to_peers(snapshot)
```

---

## Escalation and Spawn Tables

### Per-Level Entity Spawn Configuration

| Level | Phase 1 (Exploration) | Phase 2 (Pressure) | Phase 3 (Crisis) |
|-------|--------|---------|--------|
| **1** | 8× Crawler | +4× Crawler, 1× Lurker | 2× Crawler (final spawn) |
| **2** | 10× Crawler, 1× Lurker | +6× Crawler, 2× Lurker, 1× Spreader | +2× Lurker, Crisis |
| **3** | 12× Crawler, 2× Lurker | +8× Crawler, 2× Lurker, 1× Spreader, 1× Amalgam | +1× Chimera Host (if meta unlocked) |
| **4** | 14× Crawler, 2× Lurker, 1× Spreader | +10× Crawler, 3× Lurker, 2× Spreader, 1× Amalgam | +1× Chimera Host, Crisis |
| **Final** | 16× Crawler, 3× Lurker, 1× Spreader | +12× Crawler, 3× Lurker, 2× Spreader, 2× Amalgam | Chimera Host(s), maximum threat |

### Spawn Waves
Entities are spawned in **waves** timed to escalation phase:

```gdscript
var spawn_waves = [
    # Phase 1 (Exploration, 0–60s)
    { "time": 5.0, "entities": ["Crawler", "Crawler"] },
    { "time": 15.0, "entities": ["Crawler"] },
    { "time": 30.0, "entities": ["Crawler", "Crawler"] },
    { "time": 45.0, "entities": ["Crawler"] },

    # Phase 2 (Pressure, 60–120s)
    { "time": 65.0, "entities": ["Lurker"] },
    { "time": 80.0, "entities": ["Crawler", "Crawler", "Crawler"] },
    { "time": 100.0, "entities": ["Spreader"] },

    # Phase 3 (Crisis, 120s+)
    { "time": 130.0, "entities": ["Amalgam"] },
    { "time": 150.0, "entities": ["Crawler", "Crawler", "Crawler", "Crawer"] },
    { "time": 180.0, "entities": ["Chimera Host"] },  # if available
]
```

---

## Behavior Tree Template (GDScript Structure)

```gdscript
class_name CRISPRBehaviorTree
extends LimboAI.BehaviorTree

var entity: CRISPREntity

func _ready():
    # Root sequence
    root = Selector.new([
        Condition.new(func(): return entity.player_in_range()),
        Sequence.new([
            Task.new(func(): return entity.chase_player()),
            Task.new(func(): return entity.attack_if_in_range()),
        ]),
        Sequence.new([
            Task.new(func(): return entity.patrol_room()),
        ])
    ])

class Condition:
    var check: Callable
    func _init(check_func: Callable):
        check = check_func
    func tick() -> int:
        return SUCCESS if check.call() else FAILURE

class Selector:
    var children: Array
    func _init(child_array: Array):
        children = child_array
    func tick() -> int:
        for child in children:
            var result = child.tick()
            if result == SUCCESS:
                return SUCCESS
        return FAILURE

class Sequence:
    var children: Array
    func _init(child_array: Array):
        children = child_array
    func tick() -> int:
        for child in children:
            var result = child.tick()
            if result == FAILURE:
                return FAILURE
        return SUCCESS
```

---

## AI Configuration per Difficulty

### Difficulty Modifiers

| Difficulty | Spawn Rate | Speed | Damage | Detection Range |
|------------|-----------|-------|--------|-----------------|
| **Normal** | 1.0x | 1.0x | 1.0x | 1.0x |
| **Hard** | 1.3x | 1.1x | 1.2x | 1.2x |
| **Challenge (Daily)** | 1.5x | 1.2x | 1.4x | 1.3x |

---

## Testing Checkpoints

- [ ] Crawler chases player when detected, attacks in melee range, idle otherwise.
- [ ] Lurker ambushes with 1s telegraph, high-damage burst attack.
- [ ] Spreader leaves contamination zones (3m radius, 1 dmg/s) as it moves.
- [ ] Amalgam is slow, tanky, and immune to knockback. Blocks corridors.
- [ ] Chimera Host uses teleport, projectile vomit, and grab ability. Drops rare tool on death.
- [ ] Entity snapshots broadcast every 0.1s in multiplayer. Clients see smooth entity movement.
- [ ] Spawn waves occur on schedule. Phase transitions (Exploration → Pressure → Crisis) trigger entity type unlocking.
- [ ] Death removes entity from level; body despawns after 2s.

---

## Implementation Notes

1. **LimboAI Integration:** Behavior trees are best implemented as Resources (BT files or BehaviorTree nodes). Each entity type has one template tree.
2. **Pathfinding:** Use Godot's NavigationServer2D for Crawler/Lurker pathing (avoid walls). Amalgam moves in straight lines (simple).
3. **Detection Range:** Use Area2D for broad detection. OnBodyEntered/Exited signals for precise chase triggering.
4. **Knockback:** Apply velocity.x += force_direction * knockback_amount. Amalgam (knockback_resist=1.0) ignores this.
5. **Contamination Zone Persistence:** When Spreader leaves a zone, it remains for 20s before despawning (even if Spreader dies). Use a Timer node.
6. **Chimera Host Loot:** On death, create a ToolPickup node at death location with a Rare-tier tool (randomized).

---

## Next Steps
- **REQ-07:** Levels and presentation (tilemap design, VFX, audio integration).
- **REQ-08:** MVP build plan (phased development, checkpoints).
