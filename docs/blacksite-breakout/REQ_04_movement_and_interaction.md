# REQ_04: Movement and Interaction
**Blacksite Breakout: Escape from Area 51**

## Document Purpose
Defines player movement mechanics, input handling, interactable object types, and stealth/detection systems. Covers isometric navigation, contextual interactions, and how the player experiences the facility interface.

---

## 1. Isometric Movement System

### 1.1 Camera Perspective
- **Type:** Isometric (2D projection of 3D space, 45° overhead angle).
- **View angle:** Camera positioned at 45° above horizontal, rotated to show a north-east facing wall and a south-west facing wall equally.
- **Scale:** 1 unit in-game ≈ 1 pixel on-screen (pixel-perfect isometric).
- **Zoom levels:** Standard (1.0x), Zoomed-out (0.7x for overview), Zoomed-in (1.5x for detail).
- **Camera follow:** Camera remains centered on current entity; pans smoothly when entity moves; toggleable follow mode.

### 1.2 Click-to-Move Navigation
**Primary input method:** Mouse/cursor-based path planning.

**Flow:**
1. Player clicks on a location on screen (or uses analog stick to point, confirm with A button).
2. Game calculates path from entity's current position to clicked target using **navigation mesh** (precomputed for performance).
3. Entity auto-pathfinds to target location, avoiding obstacles.
4. When entity reaches target, it stops and waits for new input.

**Visual feedback:**
- Clicked location shows brief highlight (white circle, 0.3 seconds).
- Path to target displays as faint green line (optional, toggleable in settings).
- Entity sprite animates walk cycle matching movement speed.

### 1.3 Directional Movement (WASD / Analog Stick)
**Secondary input method:** Real-time directional input.

**Flow:**
1. Player holds WASD key (W=up, A=left, S=down, D=right) or tilts analog stick.
2. Entity moves continuously in that direction at current speed.
3. Release input to stop.
4. Entity plays walk animation in direction of movement.

**Movement Modes & Speed:**
| Mode | Input | Speed (units/sec) | Noise Radius | Visual | Audio |
|------|-------|---|---|---|---|
| **Walk** | Hold WASD normally | 150 | 10 units | Normal walk cycle | Quiet footsteps |
| **Sprint** | Hold Shift + WASD | 250 | 40 units | Faster animation, dust particles | Loud running |
| **Crawl** | Hold Ctrl + WASD (vent-only) | 75 | 2 units | Slow prone animation | No sound |

### 1.4 Pathfinding & Obstacles
- **Navigation mesh:** Pre-baked tilemap-based nav mesh; updated only on level load (not dynamic).
- **Obstacles:** Walls, closed doors, and metal barriers block movement automatically.
- **Path correction:** If target is unreachable, entity stops and alerts player (on-screen message: "Cannot reach destination").
- **Diagonal movement:** Entity moves diagonally when WASD keys are pressed simultaneously; smooth diagonal path generated.

**GDScript - Movement Controller:**
```gdscript
class_name PlayerMovementController
extends Node

@export var entity: EntityCharacter
@export var navigation: NavigationAgent2D

var target_position: Vector2 = Vector2.ZERO
var current_speed: float = 0.0
var movement_mode: int = 0  # 0 = walk, 1 = sprint, 2 = crawl

enum MovementMode { WALK = 150.0, SPRINT = 250.0, CRAWL = 75.0 }
enum NoiseLevel { WALK = 10.0, SPRINT = 40.0, CRAWL = 2.0 }

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var clicked_pos = get_global_mouse_position()
			set_target_position(clicked_pos)

func _process(delta: float) -> void:
	update_movement_mode()
	navigate_to_target(delta)
	update_noise_level()

func set_target_position(pos: Vector2) -> void:
	target_position = pos
	navigation.set_target_position(pos)

func navigate_to_target(delta: float) -> void:
	if entity.is_downed:
		return

	if not navigation.is_navigation_finished():
		var next_pos = navigation.get_next_path_position()
		var move_direction = (next_pos - entity.global_position).normalized()

		entity.velocity = move_direction * current_speed
		entity.velocity = entity.move_and_slide()
	else:
		entity.velocity = Vector2.ZERO

func update_movement_mode() -> void:
	if Input.is_action_pressed("sprint"):
		current_speed = MovementMode.SPRINT
		movement_mode = 1
	elif Input.is_action_pressed("crawl"):
		current_speed = MovementMode.CRAWL
		movement_mode = 2
	else:
		current_speed = MovementMode.WALK
		movement_mode = 0

func update_noise_level() -> void:
	var noise_values = [NoiseLevel.WALK, NoiseLevel.SPRINT, NoiseLevel.CRAWL]
	var current_noise = noise_values[movement_mode]

	if entity.velocity.length() > 0:
		get_tree().root.find_child("NoiseTracker", true, false).add_noise(current_noise, entity.global_position)
```

---

## 2. Interaction System

### 2.1 Context-Sensitive Interaction
When a player entity moves within interaction range of an interactable object, an **interaction prompt** appears on-screen.

**Flow:**
1. Entity enters proximity zone (50–100 units) of interactable.
2. Prompt appears: "[E] Interact" (or "[A] Interact" on controller).
3. Player presses interact key/button.
4. Interactable's interaction script executes.

**Visual feedback:**
- Interactable highlights (tint to yellow/gold).
- Prompt appears in bottom-right HUD corner or above interactable.
- Confirmation sound plays when interact begins.

### 2.2 Interactable Types

#### 2.2.1 Doors
**Base class:** `InteractableObject_Door` (StaticBody2D)

**Subtypes:**
- **Unlocked door:** Opens instantly; can be walked through.
- **Locked door:** Requires keycard or hacking; interact prompts "Unlock [KEYCARD REQUIRED]."
- **Alarmed door:** Opening triggers alarm escalation; guard patrols nearby may investigate.
- **Automatic door:** Sensor-triggered; opens when entity approaches; closes after 5 seconds idle.

**Interaction:**
```gdscript
class_name InteractableObject_Door
extends StaticBody2D

@export var door_type: int = 0  # 0 = unlocked, 1 = locked, 2 = alarmed, 3 = automatic
@export var requires_keycard: bool = false
@export var lock_code: String = "A1B2"
@export var alarm_system: AlarmSystem

var is_open: bool = false
var animation_player: AnimationPlayer

func _ready() -> void:
	animation_player = $AnimationPlayer

func interact(entity: EntityCharacter) -> void:
	match door_type:
		0:  # Unlocked
			open_door()
		1:  # Locked
			if entity.inventory.has_item("keycard"):
				entity.inventory.use_item("keycard")
				open_door()
			else:
				print("Keycard required")
		2:  # Alarmed
			open_door()
			alarm_system.escalate_alarm(global_position)
		3:  # Automatic
			open_door()

func open_door() -> void:
	if is_open:
		return
	is_open = true
	animation_player.play("open")
	await animation_player.animation_finished
	# Door remains open

func close_door() -> void:
	if not is_open:
		return
	is_open = false
	animation_player.play("close")
	await animation_player.animation_finished
```

#### 2.2.2 Terminals
**Base class:** `InteractableObject_Terminal` (StaticBody2D + Area2D)

**Subtypes:**
- **Information terminal:** Displays objective hints, facility data, or lore.
- **Hackable terminal:** Can be hacked by Rogue AI to unlock doors or disable cameras.
- **Objective terminal:** Reading/hacking completes sector objective.

**Interaction:**
```gdscript
class_name InteractableObject_Terminal
extends StaticBody2D

@export var terminal_type: int = 0  # 0 = info, 1 = hackable, 2 = objective
@export var hack_duration: float = 2.0
@export var hack_range: float = 100.0
@export var information_text: String = "Facility information..."

var is_hacked: bool = false

func interact(entity: EntityCharacter) -> void:
	match terminal_type:
		0:  # Information
			display_information(entity)
		1:  # Hackable
			if entity.entity_type == EntityCharacter.EntityType.ROGUE_AI:
				initiate_hack(entity)
			else:
				print("Rogue AI only")
		2:  # Objective
			complete_objective(entity)

func display_information(entity: EntityCharacter) -> void:
	var ui = get_tree().root.find_child("UILayer", true, false)
	var info_panel = ui.get_node("InformationPanel")
	info_panel.display_text(information_text)

func initiate_hack(entity: EntityCharacter) -> void:
	print("Hacking terminal...")
	await get_tree().create_timer(hack_duration).timeout
	is_hacked = true
	print("Terminal hacked!")

func complete_objective(entity: EntityCharacter) -> void:
	get_tree().root.find_child("GameManager", true, false).complete_objective()
	print("Objective completed")
```

#### 2.2.3 Vents
**Base class:** `InteractableObject_Vent` (Area2D)

**Subtypes:**
- **Entity-specific:** Only accessible to certain entity classes.
  - Replicator: Enter after assimilating metal; can carry one ally.
  - Fungus Strain: Move through at 2x speed.
  - CRISPR: Squeeze into small vents via mutation.
  - Rogue AI: Can hack vent control to open/close remotely.
- **Connected vents:** Entering one vent lists destination vents in proximity.

**Interaction:**
```gdscript
class_name InteractableObject_Vent
extends Area2D

@export var vent_type: String = "small"  # small, medium, large
@export var accessible_entities: Array[int] = [0, 1, 2, 3]  # Entity type indices
@export var connected_vents: Array[Node2D] = []

func interact(entity: EntityCharacter) -> void:
	if not is_accessible_to(entity):
		print("Cannot access vent: ", entity.entity_type)
		return

	if entity.entity_type == EntityCharacter.EntityType.REPLICATOR:
		replicator_vent_enter(entity)
	else:
		enter_vent(entity)

func is_accessible_to(entity: EntityCharacter) -> bool:
	return entity.entity_type in accessible_entities

func replicator_vent_enter(entity: EntityCharacter) -> void:
	# Check for adjacent ally
	var nearby_allies = get_tree().get_nodes_in_group("entity_character")
	var ally_to_carry = null
	for ally in nearby_allies:
		if ally != entity and entity.global_position.distance_to(ally.global_position) < 80:
			ally_to_carry = ally
			break

	if ally_to_carry:
		print("Carrying ally through vent")
		ally_to_carry.global_position = entity.global_position  # Teleport ally

	# Select destination vent
	var destination = connected_vents[0] if not connected_vents.is_empty() else null
	if destination:
		entity.global_position = destination.global_position

func enter_vent(entity: EntityCharacter) -> void:
	print("Entity entering vent")
	# Animation/fade-out
	var tween = create_tween()
	tween.tween_property(entity, "modulate", Color.TRANSPARENT, 0.5)
	await tween.finished

	# Teleport to destination
	var destination = connected_vents[0] if not connected_vents.is_empty() else null
	if destination:
		entity.global_position = destination.global_position

	tween = create_tween()
	tween.tween_property(entity, "modulate", Color.WHITE, 0.5)
```

#### 2.2.4 Items (Pickup)
**Base class:** `InteractableObject_Item` (Area2D)

**Subtypes:**
- **Keycard:** Unlocks locked doors.
- **Medkit:** Restores 30 health.
- **Tool (lockpick, data chip):** Enables specific interactions.
- **Key item (objective):** Completes sector objective when collected.

**Interaction:**
```gdscript
class_name InteractableObject_Item
extends Area2D

@export var item_type: String = "keycard"  # keycard, medkit, tool, key_item
@export var item_name: String = "Keycard"

func interact(entity: EntityCharacter) -> void:
	entity.inventory.add_item(item_type, item_name)
	print("Picked up: ", item_name)
	queue_free()
```

#### 2.2.5 Guard Encounter
**Base class:** `InteractableObject_Guard` (Area2D trigger)

**Subtypes:**
- **Patrol guard:** Walking NPC, can be avoided or engaged.
- **Stationary sentry:** Guard at fixed post.
- **Ambush trigger:** Hidden guards spawn when entity enters zone.

**Interaction:**
When entity moves into guard's line-of-sight:
- Guard switches to ALERT state.
- Alarm system escalates.
- Combat encounter initiated (guards attack, entity can flee or fight back).

**GDScript:**
```gdscript
class_name InteractableObject_Guard
extends Area2D

@export var guard_ref: ContainmentGuard
@export var alarm_system: AlarmSystem

func _on_area_entered(area: Area2D) -> void:
	if area is EntityCharacter:
		guard_ref.alert_to_entity(area)
		alarm_system.escalate_alarm(global_position)
```

---

## 3. Stealth Mechanics

### 3.1 Noise Radius
Every entity has a **noise radius** based on movement mode:

| Movement Mode | Noise Radius | Detection Distance |
|---|---|---|
| Walk | 10 units | Guards within 50 units may hear |
| Sprint | 40 units | Guards within 80 units will hear |
| Crawl | 2 units | Guards within 10 units may hear |
| Ability use | Variable (5–40) | Ability-dependent |

**Noise accumulation:** Facility tracks cumulative noise from all entities; exceeding threshold (50 points) escalates alarm.

### 3.2 Line of Sight (Guard Detection)
Guards have a **detection cone** (visual angle + distance):

**Guard detection parameters:**
- **Detection angle:** 90° (guards see roughly to left and right, not behind).
- **Detection distance:** 200 units (can spot entity up to 200 units away).
- **Line of sight:** Entity must be unobstructed by walls/obstacles.
- **Investigation:** If guard detects movement/noise, guard moves to noise source and searches.

**Entity avoidance:**
- Stay outside detection cone.
- Move behind walls or obstacles.
- Use noise-masking abilities (Fungus Strain spore cloud).
- Use distraction abilities (Replicator decoy, Rogue AI hack).

### 3.3 Shadow Zones
Certain areas on the map are darker and provide **visual cover**:
- Unlit hallways, dark alcoves, shadowed corners.
- Entities in shadow zones are harder to spot (reduce guard detection distance by 50%).
- Visual indicator: darker tile coloring on map.

**GDScript - Guard Detection:**
```gdscript
class_name GuardDetectionSystem
extends Node

@export var detection_cone_angle: float = 90.0
@export var detection_distance: float = 200.0
@export var alarm_system: AlarmSystem

func check_entity_detection(guard: ContainmentGuard, entity: EntityCharacter) -> bool:
	var distance = guard.global_position.distance_to(entity.global_position)

	# Distance check
	if distance > detection_distance:
		return false

	# Line of sight check
	var space_state = guard.get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(guard.global_position, entity.global_position)
	query.exclude = [guard]
	var result = space_state.intersect_ray(query)

	if result and result.collider != entity:
		return false  # Obstacle blocks sight

	# Angle check (detection cone)
	var to_entity = (entity.global_position - guard.global_position).normalized()
	var guard_direction = Vector2.RIGHT.rotated(guard.rotation)
	var angle_diff = rad_to_deg(acos(to_entity.dot(guard_direction)))

	if angle_diff > detection_cone_angle / 2.0:
		return false  # Outside detection cone

	# Shadow zone reduction
	if entity.is_in_shadow_zone():
		if distance > detection_distance * 0.5:
			return false  # Reduced detection range in shadows

	return true  # Entity detected

func on_entity_detected(guard: ContainmentGuard, entity: EntityCharacter) -> void:
	print("Entity detected by guard: ", entity.entity_type)
	guard.alert_to_entity(entity)
	alarm_system.escalate_alarm(entity.global_position)
```

---

## 4. Controller Input Mapping

**Primary Input Device:** Gamepad (Xbox/PlayStation compatible)

| Action | Button | Alternative (Keyboard) |
|--------|--------|---|
| Move forward | Left Stick Up | W |
| Move backward | Left Stick Down | S |
| Move left | Left Stick Left | A |
| Move right | Left Stick Right | D |
| Interact | A (Green) | E |
| Cancel/Back | B (Red) | Esc |
| Ability 1 | LB / L1 | Q |
| Ability 2 | RB / R1 | R |
| Ultimate | LT (left trigger) | T |
| Passive toggle | Y (Yellow) | Space |
| Map view | X (Blue) | M |
| Pause menu | Menu / Start | P |

**Mouse/Keyboard Alternative:**
- **Movement:** WASD or right-click drag to move.
- **Abilities:** Q, R, T (keyboard) or mouse side buttons.
- **Interact:** E key (standing near interactable).
- **Map:** M to toggle minimap overlay.

### 4.1 Input Buffering
If player presses a button during ability animation (cooldown), input is buffered and executed when cooldown ends:
```gdscript
class_name InputBuffer
extends Node

var input_queue: Array = []
var is_processing_input: bool = false

func _input(event: InputEvent) -> void:
	if event.is_pressed():
		if is_processing_input:
			input_queue.append(event)
			get_tree().root.set_input_as_handled()
		else:
			process_input(event)

func set_processing(value: bool) -> void:
	is_processing_input = value
	if not value and not input_queue.is_empty():
		var next_input = input_queue.pop_front()
		process_input(next_input)

func process_input(event: InputEvent) -> void:
	if event.is_action_pressed("ability_1"):
		entity_controller.activate_ability_1()
	elif event.is_action_pressed("ability_2"):
		entity_controller.activate_ability_2()
```

---

## 5. Camera Control

### 5.1 Camera Follow
- Camera stays centered on current entity, smoothly panning as entity moves.
- **Lag:** 0.1 seconds (smooth easing, not instant snap).
- **Zoom:** Default 1.0x (can adjust 0.7x–1.5x with mouse wheel or shoulder button + direction).

### 5.2 Map Overview Mode
- Player presses **X (Map View)** to toggle overhead map.
- Map shows entire sector layout, fog of war, entity positions (blue dots), guard positions (red dots, if known).
- Player can click on map to set movement target.
- Pressing X again returns to normal camera follow.

**GDScript - Camera Controller:**
```gdscript
class_name CameraController
extends Camera2D

@export var target_entity: EntityCharacter
@export var follow_smoothness: float = 0.1
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.7
@export var max_zoom: float = 1.5

var is_in_map_view: bool = false

func _process(delta: float) -> void:
	if not is_in_map_view:
		follow_entity(delta)

	handle_zoom_input()

func follow_entity(delta: float) -> void:
	var target_pos = target_entity.global_position
	global_position = global_position.lerp(target_pos, follow_smoothness)

func handle_zoom_input() -> void:
	if Input.is_action_just_scrolled_up():
		zoom.x = clamp(zoom.x + zoom_speed, min_zoom, max_zoom)
		zoom.y = zoom.x

func toggle_map_view() -> void:
	is_in_map_view = not is_in_map_view
	if is_in_map_view:
		global_position = get_viewport().get_camera_2d().global_position
		zoom = Vector2.ONE * 0.5  # Zoom out for map
	else:
		zoom = Vector2.ONE  # Reset zoom
```

---

## 6. UI/HUD Integration

### 6.1 Interaction Prompt
**Appearance:** Small text label in bottom-right HUD corner.
**Content:** "[E] Interact" or "[A] Interact" (adapts to input method).
**Behavior:** Appears when entity within 100 units of interactable; disappears when entity moves away.

### 6.2 Ability Cooldown Display
**Appearance:** Four ability icons in HUD corner (one for each ability slot).
**Content:** Icon with cooldown timer overlay (circular progress bar or text counter).
**Behavior:** Cooldown icon dims when ability unavailable; brightens when ready.

### 6.3 Entity Status
**Appearance:** Health bar, entity class name, status effects.
**Behavior:** Updates in real-time as health changes; displays incapacitation state if downed.

### 6.4 Noise Indicator
**Appearance:** Meter in HUD showing cumulative noise level (0–100).
**Behavior:** Increases as entity moves/acts; decreases over time in quiet state; turns red as threshold approaches.

---

## 7. Accessibility Features

### 7.1 Colorblind Modes
- Deuteranopia (red-green): Adjust HUD colors to use blue/yellow contrasts.
- Protanopia (red-green): Adjust to blue/yellow.
- Tritanopia (blue-yellow): Adjust to red/cyan.

### 7.2 Audio-Visual Feedback
- All audio cues (noise level, guard proximity, alarm escalation) have visual equivalents.
- Screen flashes, HUD alerts, and visual indicators supplement audio.

### 7.3 Control Remapping
- Players can remap all controller buttons in Settings.
- Accessibility profile: large font, high contrast, simplified controls.

---

## 8. Implementation Notes

### 8.1 Navigation Mesh Baking
- Pre-bake navigation mesh in Godot using TileMap + NavigationRegion2D.
- Update only on level load; not dynamic during gameplay (for performance).
- Test pathfinding in editor to ensure no unreachable areas.

### 8.2 Proximity Detection
- Use Area2D nodes for interactable proximity zones.
- Area2D signals (`area_entered`, `area_exited`) drive interaction prompt visibility.

### 8.3 Input Handling
- Centralize input handling in a single `InputManager` node per entity.
- Use action names (e.g., "move_forward", "ability_1") defined in Project Settings → Input Map.
- Avoid hardcoded key codes.

---

## 9. Related Documents
- REQ_01: Vision and Architecture (entity nodes, UI layer structure)
- REQ_02: Game State Machine (interaction state transitions)
- REQ_03: Entity Classes and Abilities (ability activation, cooldowns)
- REQ_06: Guard AI and Alarm System (detection cone, noise radius)

---

**Document Version:** 1.0
**Last Updated:** 2026-03-15
**Status:** Active
