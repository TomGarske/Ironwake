# SHARED_02: BurnBridgers GDScript Code Conventions

**Version:** 1.0
**Last Updated:** 2026-03-15
**Status:** Active

---

## 1. Language Rules

All BurnBridgers code follows strict GDScript conventions for consistency, type safety, and maintainability.

### 1.1 Type System

**Fully Typed GDScript Required:**

```gdscript
# ✓ CORRECT: All variables, parameters, return types are typed
class_name Player
extends CharacterBody2D

@export var speed: float = 200.0
@export var jump_force: float = 400.0

var velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var health: int = 100

func take_damage(amount: int) -> void:
	health -= amount

func get_distance_to(target: Vector2) -> float:
	return position.distance_to(target)

# ✗ WRONG: Untyped variables
var speed = 200.0  # Missing type annotation
var velocity  # No initialization
func take_damage(amount):  # Missing parameter & return type
	health = health - amount
```

**Type annotations in all scenarios:**
- Function parameters: `func move(delta: float) -> void:`
- Variable declarations: `var health: int = 100`
- Array/Dictionary contents: `var players: Dictionary[int, Dictionary] = {}`
- Signal parameters: `signal player_damaged(damage: int, source: Node)`

### 1.2 @export for Tunable Values

Use `@export` for any value that should be adjustable in the Godot editor:

```gdscript
class_name Enemy
extends CharacterBody2D

## Movement speed in pixels/second
@export var move_speed: float = 150.0

## How far the enemy can see the player
@export var detection_range: float = 300.0

## Damage dealt per hit
@export var attack_damage: int = 10

## Health points at spawn
@export var max_health: int = 50

## Grouped exports for organization
@export var knockback_enabled: bool = true
@export var knockback_force: float = 200.0
@export var knockback_duration: float = 0.2

func _ready() -> void:
	# Can override these at runtime too, but editor default is the intent
	health = max_health
```

**Why:** Designers can tune difficulty and balance without rebuilding or editing code.

### 1.3 @onready for Node References

**Always use `@onready` to cache node references:**

```gdscript
class_name Player
extends CharacterBody2D

## Cached node references (never string paths)
@onready var sprite: Sprite2D = $Sprite2D
@onready var animation: AnimationPlayer = $AnimationPlayer
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var health_label: Label = $UI/HealthLabel

## ✓ CORRECT: _ready uses cached references
func _ready() -> void:
	animation.animation_finished.connect(_on_animation_finished)
	attack_hitbox.body_entered.connect(_on_hitbox_entered)

## ✗ WRONG: String node paths
@onready var sprite = get_node("Sprite2D")  # Don't use strings
var anim = get_node("AnimationPlayer")  # Missing @onready, untyped

func take_damage(amount: int) -> void:
	health_label.text = "HP: %d" % health  # Uses cached reference
```

**Benefits:**
- Compile-time verification of node existence
- Better performance (cached at `_ready`)
- Refactoring safety (rename nodes in scene tree, Godot updates references)
- Autocomplete in editor

### 1.4 super() in Custom Class Hierarchies

When extending custom classes (not just built-in Godot classes), call `super()` in `_ready()`:

```gdscript
## Base class for all game entities
class_name AgentBase
extends CharacterBody2D

var health: int = 100

func _ready() -> void:
	print("AgentBase initialized")

## Derived class
class_name Player
extends AgentBase

func _ready() -> void:
	super()  # Call parent's _ready
	print("Player initialized after AgentBase")
	health = 200
```

**Note:** For built-in Godot nodes (Node, CharacterBody2D, etc.), `super()` is optional but recommended for clarity.

### 1.5 Physics: _physics_process for Movement

**Always use `_physics_process(delta)` for physics-based movement:**

```gdscript
class_name Player
extends CharacterBody2D

@export var move_speed: float = 200.0
@export var gravity: float = 800.0

var velocity: Vector2 = Vector2.ZERO

## Called every physics frame (60 FPS target)
func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y += gravity * delta

	# Input
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity.x = input_dir.x * move_speed

	# Built-in CharacterBody2D collision resolution
	velocity = move_and_slide()

## ✗ WRONG: Using _process for physics
func _process(delta: float) -> void:
	position.x += 200 * delta  # Frame-rate dependent, skips physics
```

**Why:**
- `_physics_process` is decoupled from frame rate
- `move_and_slide()` handles collisions automatically
- Deterministic in multiplayer (physics tick is fixed)

### 1.6 class_name on Every Instantiated Script

Every script that defines a class must have `class_name` at the top:

```gdscript
class_name Player
extends CharacterBody2D

var health: int = 100

## Load by class name anywhere
func spawn_player() -> void:
	var player = Player.new()
	add_child(player)

## In scenes, the script is identified by class name in the inspector
```

**Exception:** Utility/helper scripts with only static functions can omit `class_name`:

```gdscript
## Utility script (no instantiation)
static func clamp_velocity(vel: Vector2, max_speed: float) -> Vector2:
	return vel.limit_length(max_speed)
```

---

## 2. Naming Conventions

Follow consistent naming conventions across the entire project.

### 2.1 Naming Table

| Category | Convention | Example | Notes |
|---|---|---|---|
| **File Names** | snake_case | `player_controller.gd`, `health_system.gd` | Match class_name but lowercase |
| **Class Names** | PascalCase | `class_name Player`, `class_name HealthSystem` | Matches file name capitalized |
| **Functions** | snake_case | `func take_damage()`, `func _physics_process()` | Private funcs prefix `_` |
| **Variables** | snake_case | `var move_speed`, `var is_alive` | Booleans prefix `is_`, `has_` |
| **Constants** | UPPER_SNAKE_CASE | `const MAX_PLAYERS: int = 8` | Global constants all caps |
| **Signals** | snake_case | `signal health_changed`, `signal player_spawned` | Past tense for events |
| **Enums** | PascalCase (type), UPPER_SNAKE_CASE (values) | `enum State { IDLE, ATTACK, DEAD }` | Descriptive state names |
| **Node Names (in Scene)** | PascalCase | `Sprite2D`, `AttackHitbox`, `HealthBar` | Match the node type |
| **Export Variables** | snake_case | `@export var move_speed: float` | Same as regular vars |
| **Onready Variables** | snake_case | `@onready var sprite: Sprite2D` | Same as regular vars |

### 2.2 Boolean Naming

Prefix booleans with `is_`, `has_`, `can_`:

```gdscript
var is_alive: bool = true
var is_attacking: bool = false
var has_weapon: bool = false
var can_jump: bool = true
var is_grounded: bool = false

# Check with if:
if is_alive and can_jump:
	velocity.y = -jump_force
```

### 2.3 Function Naming

- Private functions (not called externally): prefix `_`
- Signal handlers: prefix `_on_`
- Getters: prefix `get_`

```gdscript
class_name Enemy
extends CharacterBody2D

## Public function: other scripts can call
func take_damage(amount: int) -> void:
	health -= amount
	damaged.emit(health)

## Private function: internal use only
func _apply_knockback(force: Vector2) -> void:
	velocity += force

## Signal handler: called when hitbox detects collision
func _on_attack_hitbox_entered(body: Node) -> void:
	if body is Player:
		take_damage(10)

## Getter: returns derived data
func get_distance_to_player(player: Node2D) -> float:
	return position.distance_to(player.position)
```

### 2.4 Enum Naming

Enums use PascalCase for the enum type, UPPER_SNAKE_CASE for values:

```gdscript
class_name Enemy
extends CharacterBody2D

enum State {
	IDLE,
	CHASE,
	ATTACK,
	DEAD
}

enum Team {
	FRIENDLY,
	ENEMY,
	NEUTRAL
}

var current_state: State = State.IDLE
var team: Team = Team.ENEMY

func _on_player_detected() -> void:
	current_state = State.CHASE
```

---

## 3. Architecture Rules

BurnBridgers uses a strict signal-driven architecture for gameplay and UI separation.

### 3.1 Signal Direction: Upward & Outward

**Signals flow upward:** Gameplay entities emit signals → game mode receives → broadcasts to UI.

```
┌──────────────────────────────────────┐
│         Game Mode Scene              │
│  (Controls match flow)               │
└──────────────────────────────────────┘
         ↑        ↑        ↑            (Signals from entities)
         |        |        |
    ┌────────┐┌────────┐┌────────┐
    │ Player ││ Enemy  ││ Boss   │
    │ (emit  ││ (emit  ││ (emit  │
    │damaged)││killed) ││ phase) │
    └────────┘└────────┘└────────┘
         ↑        ↑        ↑
    ┌────────┐┌────────┐┌────────┐
    │Health  ││ Weapon ││AI State│
    │System  ││ System ││Machine │
    └────────┘└────────┘└────────┘
         ↑                 ↑
    ┌──────────────────────────────┐
    │      UI (Status Bar, HUD)    │
    │  (Listens to signals above)  │
    └──────────────────────────────┘
```

**Rule:** Never have UI directly call gameplay functions. Instead, gameplay emits signals → UI listens.

```gdscript
## ✓ CORRECT: Player emits signal when damaged
class_name Player
extends CharacterBody2D

signal health_changed(new_health: int)
signal died

var health: int = 100

func take_damage(amount: int) -> void:
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		died.emit()

## UI listens to the signal
class_name HealthBar
extends ProgressBar

func _ready() -> void:
	var player = get_tree().get_first_child_in_group("player")
	player.health_changed.connect(_on_health_changed)

func _on_health_changed(new_health: int) -> void:
	value = new_health


## ✗ WRONG: UI directly modifies player health
func _on_button_pressed() -> void:
	player.health -= 10  # Don't call gameplay from UI
```

### 3.2 Game Mode Scenes

Each game mode is a **self-contained scene** loaded by GameManager.switch_game_mode():

```
res://scenes/game/
├── blacksite_containment/
│   ├── main.tscn
│   ├── level_select.tscn
│   ├── arena.tscn
│   └── scripts/
│       ├── containment_game_mode.gd
│       ├── player_controller.gd
│       └── enemy_ai.gd
├── chrimera/
│   ├── main.tscn
│   └── ...
├── replicants/
│   └── ...
└── blacksite_breakout/
    └── ...
```

**Lifecycle:**
1. GameManager.switch_game_mode(mode) called
2. Previous game scene unloaded
3. New game scene instantiated + added to tree
4. Scene's _ready() called; connects to GameManager.phase_changed signal
5. When match ends, GameManager sets phase to GAME_OVER
6. Game scene receives signal, loads results screen or returns to lobby

```gdscript
## Example: blacksite_containment/scripts/containment_game_mode.gd
class_name ContainmentGameMode
extends Node

@onready var arena: Node = $Arena

func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	print("Containment mode loaded")

func _on_phase_changed(new_phase: int) -> void:
	match new_phase:
		GameManager.MatchPhase.IN_MATCH:
			arena.start_match()
		GameManager.MatchPhase.GAME_OVER:
			_show_results()

func _show_results() -> void:
	# Load results screen, tabulate scores, etc.
	pass
```

### 3.3 Shared Autoloads: Access by Name, Don't Mutate

Autoloads (GameManager, SteamManager, etc.) are accessed globally by name:

```gdscript
## ✓ CORRECT: Access autoload by name
func join_match() -> void:
	GameManager.register_player(peer_id, steam_id, username)
	SteamManager.join_lobby(lobby_id)

## Emit signals, don't mutate directly
GameManager.phase_changed.emit(GameManager.MatchPhase.IN_MATCH)

## ✗ WRONG: Creating local references or modifying state directly
var mgr = GameManager  # Redundant
mgr.players.clear()  # Side effect; use a signal-based API instead
```

**Pattern for safe mutations:**

```gdscript
## GameManager provides RPCs for safe state changes
@rpc("authority", "call_local", "reliable")
func set_match_phase(new_phase: MatchPhase) -> void:
	current_phase = new_phase
	phase_changed.emit(new_phase)

## Child nodes call it via RPC
func start_match() -> void:
	GameManager.set_match_phase.rpc(GameManager.MatchPhase.IN_MATCH)
```

---

## 4. Common Patterns

### 4.1 Adding a New Game Mode

**Step-by-step checklist:**

1. **Register in GameManager enum:**
   ```gdscript
   enum GameMode { BLACKSITE_CONTAINMENT, CHRIMERA, REPLICANTS, BLACKSITE_BREAKOUT, MY_MODE }
   ```

2. **Add scene path constant:**
   ```gdscript
   const MY_MODE_SCENE_PATH: String = "res://scenes/game/my_mode/main.tscn"
   ```

3. **Add music profile in _get_music_profile_for_mode():**
   ```gdscript
   GameMode.MY_MODE:
       return MusicManager.MusicProfile.new(1.1, 1.0, 1.0)  # intensity, speed, tone
   ```

4. **Add RPC handler (if mode-specific logic):**
   ```gdscript
   @rpc("authority", "call_local", "reliable")
   func on_my_mode_started() -> void:
       # Initialize mode-specific state
       pass
   ```

5. **Create scene & root script:**
   ```gdscript
   # res://scenes/game/my_mode/main.tscn
   # Root node script: res://scenes/game/my_mode/scripts/my_game_mode.gd

   class_name MyGameMode
   extends Node

   func _ready() -> void:
       GameManager.phase_changed.connect(_on_phase_changed)
   ```

6. **Define AI behavior trees:**
   ```
   res://scenes/ai/trees/my_mode/
   ├── entity_ai.tres
   ├── patrol.tres
   └── chase.tres
   ```

7. **Document in game-specific REQ_01**

### 4.2 Adding a New Entity (Player / Enemy / NPC)

**Follow the AgentBase pattern:**

```gdscript
## Base class for all entities with health & animation
class_name AgentBase
extends CharacterBody2D

@export var max_health: int = 100
@export var knockback_force: float = 200.0

var health: int
var velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT

signal died
signal health_changed(new_health: int)

func _ready() -> void:
	health = max_health
	# Initialize components
	%HealthBar.max_value = max_health
	%Hitbox.area_entered.connect(_on_hitbox_entered)

func _physics_process(delta: float) -> void:
	# Subclass implements movement
	pass

func take_damage(amount: int) -> void:
	health = max(0, health - amount)
	health_changed.emit(health)
	if health == 0:
		died.emit()
		_die()

func _apply_knockback(force: Vector2) -> void:
	velocity += force
	# Knockback decays over 10 frames
	for _i in range(10):
		velocity = velocity.lerp(Vector2.ZERO, 0.2)
		await get_tree().physics_frame

func _die() -> void:
	animation.play("death")
	await animation.animation_finished
	queue_free()

func _on_hitbox_entered(area: Area2D) -> void:
	if area.is_in_group("attacks"):
		take_damage(area.damage)


## Derived: Player
class_name Player
extends AgentBase

@export var move_speed: float = 200.0

@onready var state_machine: LimboHSM = $HSM

func _ready() -> void:
	super()
	state_machine.initialize()

func _physics_process(delta: float) -> void:
	var input = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity.x = input.x * move_speed
	velocity = move_and_slide()


## Derived: Enemy with AI
class_name Enemy
extends AgentBase

@onready var behavior_tree: BTPlayer = $BTPlayer

func _ready() -> void:
	super()
	behavior_tree.behavior_tree = load("res://scenes/ai/trees/%s/entity_ai.tres" % GameManager.selected_game_mode)
	behavior_tree.set_blackboard_var("owner", self)
	behavior_tree.set_blackboard_var("target", _find_closest_player())

func _physics_process(delta: float) -> void:
	velocity = move_and_slide()

func _find_closest_player() -> Node:
	var players = get_tree().get_nodes_in_group("players")
	if not players:
		return null
	return players.min_by(func(p): return position.distance_to(p.position))
```

### 4.3 Health Component Pattern

```gdscript
class_name HealthComponent
extends Node

@export var max_health: int = 100

var health: int

signal health_changed(new_value: int)
signal died

func _ready() -> void:
	health = max_health

func take_damage(amount: int) -> void:
	health = max(0, health - amount)
	health_changed.emit(health)
	if health == 0:
		died.emit()

func heal(amount: int) -> void:
	health = min(health + amount, max_health)
	health_changed.emit(health)
```

### 4.4 Hitbox / Hurtbox Pattern

```gdscript
## Hitbox: deals damage when it touches hurtboxes
class_name Hitbox
extends Area2D

@export var damage: int = 10

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if area is Hurtbox:
		area.take_damage(damage, global_position)


## Hurtbox: receives damage
class_name Hurtbox
extends Area2D

@onready var health: HealthComponent = %HealthComponent

func take_damage(amount: int, source_pos: Vector2) -> void:
	health.take_damage(amount)
	# Optional knockback
	var knockback_dir = (global_position - source_pos).normalized()
	get_parent().velocity += knockback_dir * 200.0
```

### 4.5 State Machine with Signals

```gdscript
class_name PlayerStateMachine
extends LimboHSM

func _ready() -> void:
	var idle_state = LimboState.new()
	idle_state.setup(func(): _on_enter_idle(), func(delta): _on_idle(delta), func(): _on_exit_idle())

	var run_state = LimboState.new()
	run_state.setup(func(): _on_enter_run(), func(delta): _on_run(delta))

	add_state("idle", idle_state)
	add_state("run", run_state)

	idle_state.add_transition("run", "run", func(): Input.is_action_pressed("ui_right"))
	run_state.add_transition("idle", "idle", func(): not Input.is_action_pressed("ui_right"))

	set_initial_state(idle_state)
	initialize()

func _on_enter_idle() -> void:
	print("Entered idle state")
	get_parent().animation.play("idle")

func _on_idle(_delta: float) -> void:
	pass

func _on_exit_idle() -> void:
	print("Left idle state")

func _on_enter_run() -> void:
	print("Entered run state")
	get_parent().animation.play("run")

func _on_run(_delta: float) -> void:
	var input = Input.get_axis("ui_left", "ui_right")
	get_parent().velocity.x = input * 200.0
```

---

## 5. Anti-Patterns to Avoid

### 5.1 String Node Paths

❌ **WRONG:**
```gdscript
var sprite = get_node("Sprite2D")
var animation = get_node("AnimationPlayer")
var health_bar = get_node("UI/HealthBar")
```

✓ **CORRECT:**
```gdscript
@onready var sprite: Sprite2D = $Sprite2D
@onready var animation: AnimationPlayer = $AnimationPlayer
@onready var health_bar: ProgressBar = %HealthBar  # Using unique names
```

### 5.2 _process for Physics

❌ **WRONG:**
```gdscript
func _process(delta: float) -> void:
	position.x += velocity.x * delta
```

✓ **CORRECT:**
```gdscript
func _physics_process(delta: float) -> void:
	velocity = move_and_slide()
```

### 5.3 Direct Sibling System Calls

❌ **WRONG:**
```gdscript
# In Player script, directly calling Enemy methods
enemy.take_damage(10)
```

✓ **CORRECT:**
```gdscript
# Use Hitbox/Hurtbox system or RPC
if area is Hurtbox:
	area.take_damage(10, global_position)
```

### 5.4 Forgetting to Disconnect Signals

❌ **WRONG:**
```gdscript
func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	# If this node is freed before disconnecting, memory leak

func _exit_tree() -> void:
	# No cleanup!
	pass
```

✓ **CORRECT:**
```gdscript
func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)

func _exit_tree() -> void:
	GameManager.phase_changed.disconnect(_on_phase_changed)
```

**Or use weak references (Godot 4.2+):**
```gdscript
func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed, CONNECT_ONE_SHOT)
	# Or use callable() with CONNECT_ONE_SHOT
```

### 5.5 Area2D Without Checking Collision Layers

❌ **WRONG:**
```gdscript
func _on_hitbox_entered(area: Area2D) -> void:
	if area.name == "Enemy":  # Fragile string comparison
		take_damage(10)
```

✓ **CORRECT:**
```gdscript
# In enemy hurtbox: set collision layer to "hurtbox" (8)
# In player hitbox: set collision mask to include "hurtbox"

func _on_hitbox_entered(area: Area2D) -> void:
	if area is Hurtbox:  # Type-safe check
		area.take_damage(damage, global_position)
```

### 5.6 Hardcoded peer_id Assumptions

❌ **WRONG:**
```gdscript
# Assuming host is peer 1
if multiplayer.get_unique_id() == 1:
	print("I'm the host")
```

✓ **CORRECT:**
```gdscript
if multiplayer.is_server():
	print("I'm the host")

var my_peer_id = multiplayer.get_unique_id()
```

---

## 6. Performance Conventions

BurnBridgers targets **60 FPS with 1–8 players**.

### 6.1 Frame Rate Target

- **Physics:** 60 Hz (fixed time step)
- **Rendering:** 60 FPS (frame rate independent)
- **Profiler threshold:** Profile every 30 seconds to detect regressions

### 6.2 Navigation Path Recalculation

Limit pathfinding updates:

```gdscript
class_name Enemy
extends AgentBase

@export var pathfind_update_interval: float = 0.25  # Max once per 0.25s

var last_pathfind_time: float = 0.0
var current_path: PackedVector2Array = []

func _physics_process(delta: float) -> void:
	if Time.get_ticks_msec() - last_pathfind_time > pathfind_update_interval * 1000:
		_recalculate_path()
		last_pathfind_time = Time.get_ticks_msec()

	# Follow current_path
	velocity = move_and_slide()

func _recalculate_path() -> void:
	var target = _find_closest_player()
	if target:
		# Use NavigationServer2D, not every frame
		current_path = NavigationServer2D.query_path(global_position, target.global_position)
```

### 6.3 Squared Distance Comparisons

Avoid `sqrt()` in tight loops:

```gdscript
# ✗ WRONG: sqrt is expensive
if position.distance_to(enemy.position) < 100:
	_attack()

# ✓ CORRECT: squared distance comparison
if position.distance_squared_to(enemy.position) < 100 * 100:
	_attack()
```

### 6.4 Facing Direction: Update Every 3+ Frames

Avoid updating rotation every frame; only when direction changes significantly:

```gdscript
class_name AgentBase
extends CharacterBody2D

var facing: Vector2 = Vector2.RIGHT
var frame_count: int = 0

func _physics_process(delta: float) -> void:
	velocity = move_and_slide()

	# Update facing direction only every 3 frames
	frame_count += 1
	if frame_count >= 3 and velocity.length() > 10:
		facing = velocity.normalized()
		frame_count = 0
		_apply_facing_direction()

func _apply_facing_direction() -> void:
	sprite.flip_h = facing.x < 0
```

---

## 7. Project Folder Layout

BurnBridgers follows this directory structure:

```
BurnBridgers/
├── addons/
│   ├── godotsteam/           # GodotSteam GDExtension (downloaded by setup)
│   └── procedural_music/
│       ├── music_manager.gd
│       └── ...
│
├── demo/
│   ├── offline_test_scene.tscn
│   └── quick_test.gd
│
├── docs/
│   ├── shared/
│   │   ├── SHARED_01_engine_and_infrastructure.md
│   │   └── SHARED_02_gdscript_conventions.md
│   ├── games/
│   │   ├── blacksite_containment/
│   │   │   ├── REQ_01_overview.md
│   │   │   ├── REQ_02_scenes.md
│   │   │   ├── REQ_03_player.md
│   │   │   ├── REQ_04_enemies.md
│   │   │   ├── REQ_05_mechanics.md
│   │   │   └── REQ_06_ai_behavior_trees.md
│   │   ├── chrimera/
│   │   ├── replicants/
│   │   └── blacksite_breakout/
│   └── CLAUDE.md
│
├── scenes/
│   ├── screens/
│   │   ├── home_screen.tscn
│   │   ├── home_screen.gd
│   │   ├── lobby.tscn
│   │   └── lobby.gd
│   │
│   ├── game/
│   │   ├── blacksite_containment/
│   │   │   ├── main.tscn
│   │   │   ├── arena.tscn
│   │   │   ├── level_select.tscn
│   │   │   └── scripts/
│   │   │       ├── containment_game_mode.gd
│   │   │       ├── player_controller.gd
│   │   │       ├── enemy_ai.gd
│   │   │       └── ...
│   │   │
│   │   ├── chrimera/
│   │   │   ├── main.tscn
│   │   │   └── scripts/
│   │   │
│   │   ├── replicants/
│   │   │   └── ...
│   │   │
│   │   └── blacksite_breakout/
│   │       └── ...
│   │
│   └── ai/
│       ├── trees/
│       │   ├── blacksite_containment/
│       │   │   ├── entity_ai.tres
│       │   │   ├── patrol.tres
│       │   │   └── chase.tres
│       │   ├── chrimera/
│       │   ├── replicants/
│       │   └── blacksite_breakout/
│       │
│       └── tasks/
│           ├── movement_task.gd
│           ├── attack_task.gd
│           └── ...
│
├── scripts/
│   ├── autoload/
│   │   ├── game_manager.gd
│   │   ├── steam_manager.gd
│   │   ├── game_constants.gd
│   │   └── ...
│   │
│   ├── screens/
│   │   ├── home_screen_ui.gd
│   │   └── lobby_ui.gd
│   │
│   ├── game_modes/
│   │   ├── blacksite_containment_mode.gd
│   │   ├── chrimera_mode.gd
│   │   ├── replicants_mode.gd
│   │   └── blacksite_breakout_mode.gd
│   │
│   ├── shared/
│   │   ├── agent_base.gd
│   │   ├── health_component.gd
│   │   ├── hitbox.gd
│   │   ├── hurtbox.gd
│   │   └── state_machine_base.gd
│   │
│   └── ui/
│       ├── health_bar.gd
│       ├── player_status_hud.gd
│       ├── scoreboard.gd
│       └── settings_menu.gd
│
├── assets/
│   ├── sprites/
│   │   ├── player/
│   │   │   ├── idle.png
│   │   │   ├── run.png
│   │   │   └── attack.png
│   │   ├── enemies/
│   │   └── ui/
│   │
│   ├── sounds/
│   │   ├── sfx/
│   │   │   ├── attack.wav
│   │   │   ├── hit.wav
│   │   │   └── death.wav
│   │   └── music/
│   │       └── (generated by MusicManager at runtime)
│   │
│   └── fonts/
│       ├── roboto_bold.ttf
│       └── jetbrains_mono.ttf
│
├── steam_appid.txt
├── project.godot
├── setup-mac.sh
├── setup-steamos.sh
└── setup-windows.ps1
```

### 7.1 Directory Responsibilities

| Directory | Purpose |
|---|---|
| `addons/` | External add-ons and GDExtensions (GodotSteam, procedural music) |
| `demo/` | Quick offline testing scenes |
| `docs/` | All documentation (REQ files, guides) |
| `scenes/screens/` | Home, Lobby UI scenes |
| `scenes/game/[mode]/` | Per-game mode scenes & scripts |
| `scenes/ai/trees/` | Behavior tree `.tres` files |
| `scripts/autoload/` | Global singletons (GameManager, SteamManager) |
| `scripts/shared/` | Shared entity base classes (AgentBase, HealthComponent) |
| `scripts/game_modes/` | Per-mode coordinator scripts |
| `scripts/ui/` | UI logic & theme controllers |
| `assets/sprites/` | All PNG/image assets |
| `assets/sounds/` | WAV/OGG sound effects & music |
| `assets/fonts/` | TTF/OTF font files |

---

## 8. Common Godot 4 Features Used

### 8.1 Signals in GDScript 4

```gdscript
signal health_changed(new_value: int)
signal player_died(killer: Node, victim: Node)

func take_damage(amount: int) -> void:
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		player_died.emit(attacker, self)
```

### 8.2 Typed Callable & Lambda Functions

```gdscript
# Typed callable
var my_callback: Callable = func(x: int) -> int: return x * 2

# Lambda in signal connection
idle_state.add_transition("run", "run", func(): velocity.x > 10)

# Bind extra arguments
state_machine.state_changed.connect(_on_state_changed.bind(player_id))
```

### 8.3 Unique Names (%)

```gdscript
# In scene tree, set a node as "Unique Name" (%)
@onready var health_bar = %HealthBar  # Finds it anywhere in tree
@onready var sprite = %Sprite2D
```

---

## 9. Quick Reference: Common Tasks

### 9.1 Create a New Entity

1. Extend `AgentBase`
2. Add `@onready` references to child nodes
3. Override `_physics_process()` for movement
4. Emit signals when state changes (damaged, died, etc.)

### 9.2 Connect a Signal

```gdscript
func _ready() -> void:
	player.health_changed.connect(_on_player_health_changed)
	player.died.connect(_on_player_died)

func _on_player_health_changed(new_health: int) -> void:
	health_bar.value = new_health

func _on_player_died() -> void:
	show_death_screen()
```

### 9.3 Emit an RPC

```gdscript
# Host broadcasts to all
if multiplayer.is_server():
	broadcast_game_state.rpc(new_state)

@rpc("authority", "call_local", "reliable")
func broadcast_game_state(state: Dictionary) -> void:
	process_state(state)
```

### 9.4 Load a Scene

```gdscript
var scene = load("res://scenes/game/my_mode/main.tscn")
var instance = scene.instantiate()
add_child(instance)
```

---

## 10. Summary

| Topic | Key Rule |
|---|---|
| **Types** | Fully typed GDScript always |
| **Exports** | @export for tunable values |
| **References** | @onready for node caches, never string paths |
| **Physics** | _physics_process for movement, move_and_slide for collisions |
| **Naming** | snake_case for functions/variables, PascalCase for classes |
| **Signals** | Upward direction: gameplay → UI, never UI → gameplay |
| **Autoloads** | Access by name, don't mutate directly, use signal APIs |
| **Anti-patterns** | Avoid string paths, _process for physics, direct sibling calls |
| **Performance** | 60 FPS target, pathfind max 0.25s, squared distances, facing every 3 frames |
| **Structure** | AgentBase for entities, Hitbox/Hurtbox for collisions, LimboHSM for state |

---

**End of SHARED_02**
