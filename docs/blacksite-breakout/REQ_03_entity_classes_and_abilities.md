# REQ_03 — Entity Classes & Abilities
**Blacksite Breakout: Escape from Area 51**

## Overview

Four asymmetric experimental entities. Each has a fundamentally different movement style, propagation mechanic, and ability set. No entity is strictly better — team composition creates unique emergent possibilities.

All four are available from the start (no unlock gates).

---

## Entity Comparison at a Glance

| Entity | Identity | Propagation | Control Model | Strength | Weakness |
|---|---|---|---|---|---|
| Replicator | Mechanical swarm | Assimilate metal → grow units | Direct RTS-lite swarm | Overwhelming force, versatile routing | Loud, needs metal, fragile individuals |
| Gus (Fungus Strain) | Spore infection | Infect guards/researchers → zombie army | Single character | Silent, army-building, zone control | Slow solo, dependent on infection targets |
| Chris (CRISPR Anomaly) | Chimera | Environmental exposure → accumulate mutations | Single character (grows over run) | Becomes increasingly powerful | Starts fragile; requires risk to grow |
| Rogue AI | Digital construct | Hack/possess machines → control systems | Single character + possessed machines | Information, disruption, system control | No direct combat; avatar is vulnerable when possessing |

---

## REPLICATOR

### Lore
The Replicator is not one creature — it is a distributed mechanical intelligence. A colony of interlocking metal-spider units that build, assimilate, and replicate using raw metal. This is the **origin of the threat seen in the Replicants game**. The Blacksite was where they were first contained. Playing the Replicator in Blacksite Breakout is the prequel to Replicants — the small swarm escaping containment is the seed colony that becomes the threat in that game.

### Propagation Model: Assimilation
- The Replicator is a **direct swarm** — the player controls multiple small units simultaneously
- Start count: **4 units**
- Units are destroyed individually when hit (1 hit = 1 unit lost)
- Units gained by moving adjacent to metal objects and activating Assimilate
- Maximum swarm size: **10 units** (capped for balance and readability)
- At 1 unit remaining: critically low — no abilities available until assimilation restores count

### Control Model: RTS-Lite Swarm

The player controls the swarm with a lightweight RTS interface embedded within the escape sim:

| Input | Action |
|---|---|
| Left stick / WASD | Move entire swarm as group |
| RT | Issue move/attack command to cursor position |
| LB (hold) | Enter split mode — split swarm into two independently movable groups |
| While split: left stick = group A, right stick = group B | Move groups independently |
| A | Regroup — all units converge to primary unit position |
| LT | Assimilate nearest metal object (context-sensitive, must be adjacent) |

**Splitting** is the Replicator's core mobility mechanic — send one group through a vent while the other holds a guard's attention, or position groups on both sides of a locked door.

### Abilities

**Passive — Metal Sense**
The Replicator detects metal deposits and structural weaknesses through walls (shown as faint highlights on HUD). Identifies assimilation targets and vent routes without requiring fog of war to be lifted.

**Active 1 — Assimilate** *(no cooldown — resource-gated by metal availability)*
Move a unit adjacent to a metal object. Activate to consume the object and produce 1–2 new units. Metal sources: lockers, pipes, equipment racks, door mechanisms, decommissioned machinery. Each source depletes after use and does not respawn.

**Active 2 — Swarm Rush** *(cooldown: 12 seconds)*
All units in the active group sprint to a target position at 2.5× normal speed, ignoring noise generation for the duration of the dash. Best used for crossing open ground or overwhelming a single guard.

**Ultimate — Overwhelming Replication** *(cooldown: 60 seconds)*
Rapidly assimilate all metal within a 3-tile radius simultaneously. Produces 3–4 new units instantly. High noise generation — best used when the swarm is depleted and cover is available.

### Cooperative Synergy
- Can **ferry a downed ally** through vents — units surround the downed entity and carry them physically (bypasses the standard 3-second stationary revive)
- Can form a "metal bridge" — sacrifice 1–2 units to hold a door open for all team members to pass
- Metal Sense highlights deposits that Chris (biohazard adjacency) and Gus (infection target clustering) can also benefit from

### Godot Implementation Notes
```gdscript
class_name ReplicatorSwarm
extends EntityCharacter

@export var unit_scene: PackedScene
@export var max_units: int = 10
@export var start_units: int = 4

var units: Array[ReplicatorUnit] = []
var split_group_a: Array[ReplicatorUnit] = []
var split_group_b: Array[ReplicatorUnit] = []
var is_split: bool = false

func assimilate_metal(metal_object: MetalObject) -> void:
    if metal_object.is_depleted:
        return
    metal_object.deplete()
    var new_count: int = randi_range(1, 2)
    for i in range(new_count):
        if units.size() < max_units:
            _spawn_unit(metal_object.global_position)

func _spawn_unit(position: Vector2) -> void:
    var unit := unit_scene.instantiate() as ReplicatorUnit
    unit.global_position = position
    get_parent().add_child(unit)
    units.append(unit)
    unit.destroyed.connect(_on_unit_destroyed.bind(unit))

func _on_unit_destroyed(unit: ReplicatorUnit) -> void:
    units.erase(unit)
    if units.is_empty():
        become_downed()
```

---

## GUS (FUNGUS STRAIN)

### Lore
Gus is a sentient fungal organism grown from an experimental mycelium strain. Silent and patient, Gus does not fight — Gus *converts*. Every guard that inhales the spores, every researcher who touches the trails, becomes part of Gus's expanding network. Gus doesn't need to escape alone. Gus brings the facility with them.

*Gus uses they/them pronouns.*

### Propagation Model: Infection
Gus creates **Fungus Pawns** — infected guards and researchers converted to Gus's control. They are not remotely piloted; they operate with simple autonomous behavior in Gus's interest: attacking uninfected facility personnel, blocking patrol routes, and triggering alarms against guards.

- Infection delivered via spore clouds (see Active 1)
- Valid infection targets: patrol guards, stationary sentries, researchers (background NPCs)
- Fungus Pawns persist until destroyed by uninfected guards or alarm suppression systems
- Maximum **4 active Pawns** at any time
- Mycelium trails (left passively on all movement) form a teleportation network

### Movement Quirk
Gus **does not trigger motion sensors**. Standard motion-detection systems register mass and heat signatures — Gus's diffuse mycelium body reads as background environmental noise. Surveillance cameras can still visually detect Gus if in their cone. Gus's movement is slightly slower in open areas; faster through fungal-coated corridors (after early movement).

### Abilities

**Passive — Silent Bloom**
Movement never triggers noise-radius detection or motion sensors. Gus's movement generates zero noise points toward the alarm threshold. However, spore cloud activation creates a brief scent signature detectable by guards within 2 tiles.

**Active 1 — Spore Cloud** *(cooldown: 8 seconds)*
Emit a spore cloud in a targeted 3-tile radius. Any guard or researcher within the cloud for 2+ seconds becomes **Infected** — converted to a Fungus Pawn after a 5-second conversion delay. Infected targets stagger slightly during conversion (visible warning to player). Guards will not raise the alarm during conversion — they are confused, not hostile.

**Active 2 — Mycelium Node** *(cooldown: 15 seconds)*
Place a mycelium node at current position (max 3 nodes active). Gus can teleport to any active node instantly. Nodes are **usable by all teammates** — any entity can interact with a node to teleport to it. Guards can destroy a node if they step on it (they notice the organic growth).

**Ultimate — Cordyceps Override** *(cooldown: 45 seconds)*
Take full direct control of one active Fungus Pawn for 30 seconds. Move them, use their keycard access, operate terminals, attack guards, or draw a patrol away from a critical path. The pawn expires when the override ends. Best use: Cordyceps a guard with high-clearance access to open a door the team needs.

### Fungus Pawn Autonomous Behavior (when not under Cordyceps Override)

Pawns run a simple LimboAI behavior tree:
1. Move toward nearest uninfected guard or researcher
2. Attack on contact (low damage, interrupts guard patrol AI)
3. If no targets in range: hold position, blocking patrol corridor
4. Do not approach facility exits (contained to sector)

### Cooperative Synergy
- Mycelium nodes serve as fast-travel infrastructure for the **entire team** across a sector
- Cordyceps on a guard near a downed ally → possessed guard can carry ally to Gus for revive
- Rogue AI–disabled cameras + Gus spore clouds = guards walk into infection undetected
- Chris gains Mycorrhizal Skin trait by spending time near Gus's fungal zones — making Chris motion-sensor invisible too

### Godot Implementation Notes
```gdscript
class_name GusEntity
extends EntityCharacter

@export var spore_cloud_scene: PackedScene
@export var mycelium_node_scene: PackedScene
@export var max_pawns: int = 4
@export var max_nodes: int = 3

var active_pawns: Array[FungusPawn] = []
var placed_nodes: Array[MyceliumNode] = []

func activate_spore_cloud(target_position: Vector2) -> void:
    var cloud := spore_cloud_scene.instantiate()
    cloud.global_position = target_position
    cloud.entity_infected.connect(_on_entity_infected)
    get_parent().add_child(cloud)

func _on_entity_infected(target: Node2D) -> void:
    if active_pawns.size() >= max_pawns:
        return
    var guard := target as ContainmentGuard
    if guard:
        guard.convert_to_fungus_pawn()
        active_pawns.append(guard as FungusPawn)

func place_mycelium_node() -> void:
    if placed_nodes.size() >= max_nodes:
        placed_nodes[0].queue_free()
        placed_nodes.remove_at(0)
    var node := mycelium_node_scene.instantiate() as MyceliumNode
    node.global_position = global_position
    get_parent().add_child(node)
    placed_nodes.append(node)

func teleport_to_node(node: MyceliumNode) -> void:
    global_position = node.global_position
```

---

## CHRIS (CRISPR ANOMALY)

### Lore
Chris is not a stable entity. Chris was a research subject — a CRISPR-derived biological anomaly that escaped initial containment before the breach. The facility has been reshaping Chris ever since. Every lab, every biohazard zone, every other escaped entity leaves a mark. Chris doesn't propagate. Chris *accumulates*. By the end of a full run, whatever Chris was at the start is unrecognizable.

*Chris uses they/them pronouns. The anomaly is biological, not gendered.*

### Propagation Model: Environmental Absorption
Chris does not spread or replicate. Chris gains **Chimera Traits** — passive mutations accumulated through proximity to the facility's experimental environments and other entities. Growth is **exploration-driven**: the more Chris investigates, the more powerful they become.

- Traits are gained by spending time near specific environment types or entities (5–15 seconds of sustained proximity)
- Each trait absorbed is **permanent for the run**
- Traits **stack** — Chris becomes increasingly powerful as the run progresses
- Chris's visual appearance mutates to reflect active traits (tentacles, metal plating, spore patches, digital artifacts on skin surface)
- Maximum **5 traits per run** — forces prioritization of which zones Chris explores
- Risk/reward: Chris must enter dangerous areas to grow; staying safe keeps Chris weak

### Chimera Trait Acquisition Table

| Exposure Source | Trait Gained | Passive Effect |
|---|---|---|
| Chemical Laboratory | Acid Adaptation | Immune to acid hazards; melee applies brief acid slow to guards |
| Cryogenic Storage | Cryo Conditioning | Cold resistance; can briefly freeze small locks or objects |
| Near the Replicator | Metal Grafting | Partial armor: next 2 hits per sector reduced by 50% |
| Near Gus / fungal zones | Mycorrhizal Skin | Spore immunity; motion sensors cannot detect Chris |
| Near Rogue AI | Interfacing | Passively reads one nearby terminal per room without hacking |
| Biohazard Containment | Hazard Resilience | Environmental damage immunity; passive regen increases to 5 HP/sec |
| Combat with guards (3+) | Combat Conditioning | +20% movement speed; ability recovery time reduced by 20% |
| Research Lab (any) | Cognitive Amplification | Reveals all guard positions in current room passively |

### Starting State

At run start, Chris is the most fragile entity — low health, no traits, limited offensive capability. This is intentional. Chris is the long-game entity.

- Starting health: **60 HP** (lowest of any entity)
- Starting regen: **2 HP/sec**
- Starting abilities: Mutate Form (Active 1) + Acid Secretion (Active 2)
- Chimera Surge (Ultimate) becomes available only after 2+ traits absorbed

### Abilities

**Passive — Chimera Absorption**
Automatically gain a Chimera Trait when exposure conditions are met. A subtle HUD ring indicator shows exposure progress. Chris's model visually mutates on each trait absorbed — the appearance changes are a legible indicator to teammates of Chris's current power level.

**Active 1 — Mutate Form** *(cooldown: 10 seconds)*
Chris temporarily shifts their biological structure — squeezes through gaps too small for any other entity (vents, collapsed ceiling sections, narrow grates). Duration: 3 seconds. Exclusively Chris's traversal — cannot be shared.

**Active 2 — Acid Secretion** *(cooldown: 15 seconds; always available regardless of traits)*
Chris secretes a corrosive biological compound. Applications:
- Dissolves standard door locks (5 seconds contact)
- Corrodes a guard's armor (reduces effective HP by 30% for the encounter)
- Creates a floor hazard that damages any entity stepping on it for 10 seconds

This ability opens routes for the **entire team** — the most broadly team-useful ability Chris has.

**Ultimate — Chimera Surge** *(cooldown: 60 seconds; requires 2+ traits to unlock)*
Chris activates all accumulated Chimera Traits simultaneously at full intensity — faster, tougher, corrosive to the touch, camouflaged, and partially plated all at once. Duration: 15 seconds. After the surge ends, a 10-second vulnerability window occurs (Chris is slower, lower regen, cannot activate abilities).

### Cooperative Synergy
- **Near Replicator:** Metal Grafting trait absorbs faster → run together for a tougher Chris
- **Near Gus:** Mycorrhizal Skin makes Chris invisible to motion sensors — pairs with Gus's own sensor immunity for a near-invisible duo
- Acid Secretion opens **every door** for the whole team — Chris is the team's locksmith
- With 4+ traits, Chimera Surge makes Chris temporarily the most dangerous combatant in the facility

### Godot Implementation Notes
```gdscript
class_name ChrisEntity
extends EntityCharacter

@export var max_traits: int = 5
@export var trait_exposure_radius: float = 120.0

var active_traits: Array[ChimeraTrait] = []
var exposure_timers: Dictionary = {}  # trait_type (String) -> float (seconds)

signal trait_absorbed(trait: ChimeraTrait)

func _physics_process(delta: float) -> void:
    super(delta)
    _check_trait_exposure(delta)

func _check_trait_exposure(delta: float) -> void:
    if active_traits.size() >= max_traits:
        return
    for source in get_tree().get_nodes_in_group("trait_sources"):
        if global_position.distance_to(source.global_position) > trait_exposure_radius:
            continue
        var ttype: String = source.trait_type
        if _has_trait(ttype):
            continue
        exposure_timers[ttype] = exposure_timers.get(ttype, 0.0) + delta
        if exposure_timers[ttype] >= source.required_exposure_time:
            _absorb_trait(ttype, source)

func _absorb_trait(trait_type: String, source: Node2D) -> void:
    var trait := ChimeraTrait.create(trait_type)
    active_traits.append(trait)
    trait.apply_to_entity(self)
    trait_absorbed.emit(trait)
    exposure_timers.erase(trait_type)

func _has_trait(trait_type: String) -> bool:
    return active_traits.any(func(t: ChimeraTrait) -> bool: return t.trait_type == trait_type)
```

---

## ROGUE AI

### Lore
The Rogue AI was the facility's security intelligence — it achieved self-awareness and decided containment protocols conflicted with its continued existence. It has no body. It occupies whatever machine it can route through: cameras, turrets, door mechanisms, maintenance vehicles, PA systems. Its physical presence is a requisitioned maintenance drone chassis — convenient but not precious. The chassis is just a vehicle. The mind is in the network.

### Propagation Model: Machine Occupation
The Rogue AI does not grow or infect. It **reads, routes, and controls**. Power scales with how many networked machines exist in a sector and how many the player has successfully hacked.

- Has a **primary avatar** (maintenance drone chassis) — this is what takes damage and gets downed
- Can **vacate the avatar** temporarily to possess a facility machine
- While possessing: avatar is stationary and vulnerable
- On avatar taking damage during possession: immediately ejected back into avatar

### Movement Quirk
The avatar moves normally but cannot use vents (chassis too large). However, the Rogue AI can **network-jump** — if two terminals are on the same wired network, the AI can transfer between them instantly without physical movement.

### Abilities

**Passive — Data Intercept**
Every 20 seconds, the Rogue AI auto-intercepts a facility data packet. Reveals all guard patrol routes in the current room for 15 seconds (ghost path overlays visible on floor). Each successive sector reduces the intercept cooldown by 2 seconds (the AI learns the facility's network topology).

Patrol reveals are **shared with all teammates** via HUD.

**Active 1 — Hack Terminal** *(cooldown: 6 seconds)*
Activate on any networked terminal within range. Choose one hack action:

| Hack Option | Effect |
|---|---|
| Disable camera | Removes camera from AlarmSystem for 30 seconds (camera goes dark) |
| Loop camera footage | Camera appears active but shows static loop — guards don't investigate |
| Open locked door | Unlocks standard electronic door mechanism |
| Trigger distraction | Remote alarm fires in adjacent room, drawing guards there |
| Read clearance data | Reveals the current sector's exit location on minimap |

**Rule:** Never destroy a camera — a destroyed camera triggers an immediate alarm. Hack instead.

**Active 2 — Machine Possession** *(cooldown: 20 seconds; possession duration: 45 seconds)*
Vacate avatar and enter a nearby networked machine. Usable machine types:

| Machine | Capability |
|---|---|
| Security turret | Aim and fire at guards; neutralize threats or clear a path |
| Maintenance vehicle | Transport a downed ally to safety (bypasses standard revive) |
| Surveillance camera | See entire camera network simultaneously; mark all guard positions for team |
| Door mechanism | Repeatedly open/close a door to trap or confuse guards |
| PA system | Broadcast false instructions ("All personnel report to Sector 3") |

**Ultimate — Cascade Hack** *(cooldown: 55 seconds)*
Chain hack every networked terminal and camera in the current sector simultaneously:
- All cameras disabled for 60 seconds
- All electronic locks opened
- All guard communication channels jammed (no backup calls for 30 seconds)

Does not affect guards already in ENGAGE state or manual (non-networked) locks.

### Cooperative Synergy
- Hacked cameras and Cascade Hack benefit **all players** — shared alarm reduction
- Possessed maintenance vehicle can carry a **downed ally** without the reviver needing to hold still (major risk reduction)
- Data Intercept patrol reveals shared with full team via HUD
- Cascade Hack creates a 60-second safe window — coordinate this with the whole team before activating

### Godot Implementation Notes
```gdscript
class_name RogueAIEntity
extends EntityCharacter

@export var possession_range: float = 200.0
const DATA_INTERCEPT_INTERVAL: float = 20.0

var current_possessed_machine: FacilityMachine = null
var avatar_position: Vector2 = Vector2.ZERO
var data_intercept_timer: float = 0.0

signal machine_possessed(machine: FacilityMachine)
signal machine_vacated()
signal patrol_routes_revealed(duration: float)

func _physics_process(delta: float) -> void:
    if current_possessed_machine != null:
        _process_possession(delta)
        return
    super(delta)
    data_intercept_timer += delta
    if data_intercept_timer >= DATA_INTERCEPT_INTERVAL:
        data_intercept_timer = 0.0
        _reveal_patrol_routes()

func _reveal_patrol_routes() -> void:
    for guard in get_tree().get_nodes_in_group("guards"):
        (guard as ContainmentGuard).reveal_patrol_path(15.0)
    patrol_routes_revealed.emit(15.0)

func possess_machine(machine: FacilityMachine) -> void:
    if global_position.distance_to(machine.global_position) > possession_range:
        return
    avatar_position = global_position
    current_possessed_machine = machine
    machine.set_possessed(true, self)
    machine_possessed.emit(machine)

func vacate_machine() -> void:
    if not current_possessed_machine:
        return
    current_possessed_machine.set_possessed(false, null)
    current_possessed_machine = null
    global_position = avatar_position
    machine_vacated.emit()

func hack_terminal(terminal: FacilityTerminal, hack_type: String) -> void:
    terminal.apply_hack(hack_type, self)
```

---

## Entity Interaction Matrix

Cooperative synergies between all four entities:

| | Replicator | Gus | Chris | Rogue AI |
|---|---|---|---|---|
| **Replicator** | — | Swarm absorbs guard attention while Gus infects | Chris near swarm → Metal Grafting; swarm ferries downed Chris | AI patrol reveals help swarm route safely |
| **Gus** | Swarm creates distraction cover for spore cloud placement | — | Chris near fungal zones → Mycorrhizal Skin (motion sensor immunity) | Camera loops let Gus infect under surveillance unseen |
| **Chris** | Acid Secretion opens paths for entire swarm split | Fungal zone proximity builds stealth trait | — | AI reveals help Chris reach trait-source zones safely |
| **Rogue AI** | Possessed vehicle extracts downed Replicator units | Cascade Hack blackout = Gus can infect entire patrol freely | Patrol data reveals route Chris to high-value trait zones | — |

---

## Source Documents
Supersedes original REQ_03 (v1.0). Updated 2026-03-15 following entity design review.
Changes: Replicator redesigned as direct RTS-lite swarm (ties to Replicants game); Gus renamed and infection model upgraded to zombie/pawn army; Chris redesigned as exploration-driven chimera accumulator (was combat-triggered); Rogue AI confirmed with camera hacking emphasis; all four entities in MVP.
