# REQ_04: RTS Input and Camera
**Replicants: Swarm Command**

## Input Control Scheme

### Gamepad Controls (Primary)

| Action | Input | Function |
|--------|-------|----------|
| **Pan Camera** | Left Stick (↑↓←→) | Move camera view across the map |
| **Select/Cursor** | Right Stick (↑↓←→) or A Button | Move selection cursor or select unit |
| **Issue Command** | RT (Right Trigger) | Move/attack selected units to cursor location |
| **Context Action** | LT (Left Trigger) | Context-sensitive (harvest, assimilate, defend) |
| **Select All** | A Button | Select all units in current view |
| **Cancel Command** | B Button | Cancel current selection or command |
| **Protocol Wheel (Hold)** | X Button (hold) | Open protocol command radial menu |
| **Protocol Quick-Select** | D-Pad (↑↓←→) | Issue protocol command without menu (D-Pad Up = Rapid Replication, etc.) |
| **Zoom In** | LB (Left Bumper) or Right Trigger (hold) | Increase camera zoom (tactical close-up) |
| **Zoom Out** | RB (Right Bumper) or Left Trigger (hold) | Decrease camera zoom (strategic overview) |
| **Rotate Camera** | Y Button + Right Stick | Rotate isometric view (optional, for 3D perspective) |
| **Minimap Zoom** | Hold Minimap + Right Stick | Adjust minimap detail level |

### Keyboard/Mouse Controls (Secondary)

| Action | Input | Function |
|--------|-------|----------|
| **Pan Camera** | WASD or Arrow Keys | Move camera view |
| **Select/Cursor** | Mouse Movement | Move selection cursor |
| **Issue Command** | Left Click | Move/attack selected units to cursor location |
| **Context Action** | Right Click | Context-sensitive action |
| **Select All** | Space | Select all units in view |
| **Cancel Command** | Escape | Cancel selection/command |
| **Protocol Wheel** | Hold Z or Tab | Open protocol command wheel |
| **Protocol Quick 1** | Number 1 | Swarm Rush |
| **Protocol Quick 2** | Number 2 | Rapid Replication |
| **Protocol Quick 3** | Number 3 | Scatter |
| **Protocol Quick 4** | Number 4 | Defensive Formation |
| **Protocol Quick 5** | Number 5 | Assimilation Wave (late game) |
| **Zoom In** | Scroll Wheel Up | Zoom closer |
| **Zoom Out** | Scroll Wheel Down | Zoom farther |
| **Focus Unit** | Double Click | Center camera on selected unit |

---

## Camera System

### Camera Type
- **Top-Down Orthographic:** Fixed angle, looking directly down at the facility.
- **Optional Isometric Angle:** 45° rotation for visual depth (can be toggled in settings).
- **No First-Person:** All action is from strategic overview.

### Camera Bounds
- Constrained to map edges with a **50-pixel boundary buffer**.
- Camera cannot pan beyond the facility's outer walls.
- Soft-limit: camera centers on swarm's bounding box if no active panning.

### Zoom Levels

| Level | Scale | Use Case | FOV (pixels) |
|-------|-------|----------|-------------|
| **Strategic Overview** | 0.5× (zoom out max) | See entire map, plan strategy | ~2000×1125 |
| **Tactical** | 0.75× | Monitor multiple zones, see units clearly | ~1333×750 |
| **Default** | 1.0× | Balanced view, good for gameplay | ~1000×562 |
| **Close Tactical** | 1.5× | Focus on unit details, see specific area | ~667×375 |
| **Extreme Close** | 2.0× (zoom in max) | Inspect individual units, visual detail | ~500×281 |

### Zoom Behavior
- **Smooth interpolation:** Zoom transitions over 0.5 seconds.
- **Momentum:** Repeated zoom input continues interpolating (e.g., hold RB to smoothly zoom to max).
- **Mouse wheel:** Each scroll tick increments zoom level by 0.25× (4 ticks per level).

### Camera Follow (Soft-Focus)
- If no panning input for 2 seconds, camera **soft-follows** the swarm's center of mass.
- Soft-follow is gentle, not jarring (0.2 sec interpolation).
- Panning input **immediately breaks** soft-follow.

---

## Selection and Unit Management

### Single Unit Selection
1. **Tap cursor on unit** (Left Click or A Button near unit).
2. Unit highlights with a **blue outline**.
3. Unit's stats display on HUD (health, type, current command).
4. Selected unit can receive commands independently (Swarm Rush, move-to, etc.).

### Multiple Unit Selection
- **Box Select (Drag):** Click and drag from top-left to bottom-right corner. All units within the box are selected.
- **Select All in View:** A Button or Space. All units currently visible are selected.
- **Additive Selection (Hold Shift + Click):** Add a unit to the existing selection without clearing.
- **Deselective Selection (Hold Ctrl + Click):** Remove a unit from selection.

### Selection Persistence
- Selection **remains active** until cleared (B Button / Escape) or a new command is issued.
- Selected units are highlighted with **blue outlines**.
- If a selected unit dies, it is automatically removed from the selection.
- Maximum selection: 32 units per player (to prevent UI overflow).

### Visual Feedback
- **Selected Unit:** Bright blue outline + name/type label.
- **Hovered Unit:** Faint yellow outline (target preview).
- **Damage Indicator:** Red flash on unit when taking damage.
- **Command Indicator:** Green pulsing aura when executing a protocol command.

---

## Command Issuance

### Move Command
1. Select unit(s) with Left Click or A Button.
2. Click target location (Left Click) or press RT.
3. Selected units move to location at standard speed.
4. Command is **queued**: if units are busy, movement waits in queue.

### Attack Command
1. Select unit(s).
2. **Right Click** on an enemy (or use LT context action).
3. Selected units move to enemy and engage.
4. Combat continues until enemy is destroyed or units are commanded elsewhere.

### Context Action (LT / Right Click)
- **On Metal Deposit:** Harvester begins extraction.
- **On Resistance Unit:** Soldier begins attack.
- **On Assimilable Structure:** Assimilator begins assimilation.
- **On Facility Zone:** Units move into zone.
- **On ReplicationHub:** Show production queue and allow unit queuing.

### Protocol Command Issuance

#### Method 1: Protocol Wheel (Hold)
1. **Hold X Button** (gamepad) or **Hold Z** (keyboard).
2. **Protocol Wheel** appears (circular menu with 5 options).
3. **Move Right Stick** or **mouse cursor** to highlight protocol.
4. **Release X** or **Left Click** to confirm.
5. Cursor changes to **targeting reticle**.
6. **Press RT** or **Left Click** to confirm target location (or cancel with B).

#### Method 2: Quick-Select (D-Pad / Number Keys)
1. **D-Pad Up** → Rapid Replication (auto-target, no targeting phase).
2. **D-Pad Down** → Scatter (targets cursor location).
3. **D-Pad Left** → Defensive Formation (targets cursor location).
4. **D-Pad Right** → Swarm Rush (targets cursor location).
5. **Number 5 (Keyboard)** → Assimilation Wave (targets cursor location, late game).

#### Method 3: Context Wheel (Alternative)
- **Hold LT** to open a secondary context wheel (harvest, defend, assimilate, regroup).
- Useful for quick defensive actions without opening full protocol menu.

### Command Confirmation
- **Visual Preview:** When a protocol is selected, a **targeting indicator** (colored ring or arrow) appears at cursor.
- **Confirmation:** Press RT to confirm target, or B to cancel.
- **Feedback:** Confirmed command triggers a **chime sound** and brief animation.

---

## Camera Movement (Detailed)

### Panning
- **Left Stick** (gamepad) or **WASD** (keyboard) moves camera in that direction.
- **Acceleration:** 400 pixels/sec in panning direction.
- **Deceleration:** Smooth easing (0.2 sec) when input is released.
- **Edge Scrolling (Optional):** If cursor is within 50px of screen edge, camera pans toward edge (secondary panning option).

### Zoom
- **RB/LB (Gamepad)** or **Scroll Wheel (Keyboard/Mouse)** adjusts zoom level.
- **Zoom Duration:** 0.5 seconds (smooth interpolation).
- **Constraints:** Zoom level clamped between 0.5× and 2.0×.
- **Zoom Momentum:** Holding RB/LB causes continuous zoom until max/min is reached.

### Rotation (Optional, Isometric Only)
- **Y Button + Right Stick** (gamepad) rotates the view 45° increments.
- **Rotation Duration:** 1 second (smooth interpolation).
- **Discrete Rotation:** 4 positions (0°, 45°, 90°, 135°). Useful for viewing around tight corridors.

### Camera Reset
- **Hold Right Stick** (gamepad) or **R Key** (keyboard) to center camera on swarm's center of mass.
- **Duration:** 0.75 seconds to center.

---

## Multiplayer Input (Co-op)

### Shared Camera View
- **Local Co-op (Split-Screen or Shared View):**
  - Option 1: **Shared camera** (both players control same view, panning is consensus-based).
  - Option 2: **Picture-in-Picture:** Main camera focuses on Player 1, PiP shows Player 2's focus area.
  - Option 3: **Independent cameras** (each player has full-screen camera, shown in tutorial).

### Command Conflict Resolution
- If Player A and Player B issue conflicting commands to the same unit:
  - **Rule 1 (FIFO):** First command by timestamp takes priority. Second command is queued or rejected.
  - **Rule 2 (Consensus):** Commands that don't conflict (different units, different targets) both execute.
  - **Rule 3 (Interrupt):** If Player A's command is executing, Player B can interrupt with a Protocol command (Scatter, Rapid Replication).

### HUD Synchronization
- Both players see the same metal counter, unit roster, and assimilation progress.
- When Player A issues a command, **Player A's name** displays briefly on the HUD (e.g., "Player A issued Swarm Rush").
- Minimap updates in real-time for both players.

---

## HUD and UI Elements

### Main HUD (Top-Left)
```
┌──────────────────────────────┐
│ Metal: 47/500                │
│ Units: 12 (4H, 2S, 1B, 5Sol) │
│ Queue: Soldier (3s remaining)│
│ Assimilation: 42%            │
└──────────────────────────────┘
```
- **Metal:** Current/max metal available.
- **Units:** Total count + breakdown by type.
- **Queue:** Next replicating unit + time remaining.
- **Assimilation:** Percentage of facility assimilated.

### Protocol Wheel (Center, on-demand)
- **5-segment radial menu** with icons:
  - Up: **Rapid Replication** (spinning hub icon).
  - Right: **Swarm Rush** (forward arrow icon).
  - Down: **Scatter** (dispersing units icon).
  - Left: **Defensive Formation** (shield icon).
  - Bottom-Right: **Assimilation Wave** (absorption icon, late game).
- Each protocol shows **cost, cooldown, and description on hover**.

### Minimap (Top-Right or Bottom-Right)
```
┌────────────────────┐
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │
│ ▓ ● ● ° ▓▓▓ ◆ ▓▓▓ │
│ ▓ ● ░░░░░ ◆ ▓▓▓▓ │
│ ▓░░░░░░░░░░░░░░░░ │
│ ▓ ■ ◇ ■ ░░░░░░░░░ │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │
└────────────────────┘
Legend:
● = Swarm unit
■ = Resistance unit
◆ = Metal deposit
◇ = ReplicationHub
░ = Fog of war
▓ = Facility wall
```
- **Zoom-able:** Right Stick adjusts detail level.
- **Click-able:** Left Click on minimap pans main camera to that location.
- **Real-time:** Updates as units move.

### Radar / Alert Indicators
- **Top-right corner:** Flashing red indicator when new Resistance unit detected.
- **Alert label:** "Patrol Unit detected in North Corridor" (with icon).
- **Audio cue:** Sharp electronic beep on alert.

### Unit Information Panel (On Selection)
```
┌─ SOLDIER_3 ──────────┐
│ Type: Soldier        │
│ Health: 38/40 HP     │
│ Status: Idle         │
│ Current Command: —   │
│ Location: Zone_3     │
└──────────────────────┘
```
- Updates in real-time as unit state changes.
- Shows health bar (green → yellow → red as damage increases).

---

## Camera Scenarios

### Scenario 1: Defending a ReplicationHub
1. Player pans camera to focus on ReplicationHub and surrounding resistance units.
2. Player zooms in (1.5× level) to see unit details.
3. Player selects nearby Soldiers (box select).
4. Player issues Defensive Formation command around the hub.
5. Camera soft-follows the formed units.

### Scenario 2: Scouting New Territory
1. Player maintains strategic overview (0.5× zoom).
2. Player selects Scout and issues move command to unexplored zone.
3. Camera pans to Scout's movement.
4. As Scout reveals fog of war, new zones light up on minimap.
5. Player spot Turret, issues alert for Soldiers to focus area.

### Scenario 3: Assimilating Large Structure (Late Game)
1. Player zooms close (1.5× level) on Assimilator engaging Turret.
2. Player watches assimilation progress (visual meter).
3. As Assimilator sacrifices (Assimilation Wave), camera briefly focuses on absorption effect.
4. Camera pans out to show swarm's new positions post-protocol.

---

## GDScript Implementation Examples

### CameraController
```gdscript
# CameraController.gd
class_name CameraController
extends Camera2D

@export var pan_speed: float = 400.0
@export var zoom_speed: float = 0.25
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0
@export var zoom_duration: float = 0.5

var target_zoom: float = 1.0
var zoom_timer: float = 0.0
var pan_velocity: Vector2 = Vector2.ZERO
var map_bounds: Rect2 = Rect2(Vector2(0, 0), Vector2(2000, 1125))

signal zoom_changed(new_zoom: float)

func _ready() -> void:
	zoom = Vector2(target_zoom, target_zoom)

func _process(delta: float) -> void:
	_handle_panning(delta)
	_handle_zoom(delta)

func _handle_panning(delta: float) -> void:
	var input_direction = Vector2.ZERO
	if Input.is_action_pressed("ui_left"):
		input_direction.x -= 1
	if Input.is_action_pressed("ui_right"):
		input_direction.x += 1
	if Input.is_action_pressed("ui_up"):
		input_direction.y -= 1
	if Input.is_action_pressed("ui_down"):
		input_direction.y += 1

	if input_direction != Vector2.ZERO:
		pan_velocity = input_direction.normalized() * pan_speed
	else:
		pan_velocity = pan_velocity.lerp(Vector2.ZERO, delta * 5.0)

	global_position += pan_velocity * delta
	_constrain_camera_bounds()

func _handle_zoom(delta: float) -> void:
	if Input.is_action_just_pressed("ui_scroll_up"):
		target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)
		zoom_timer = 0.0

	if Input.is_action_just_pressed("ui_scroll_down"):
		target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)
		zoom_timer = 0.0

	if zoom_timer < zoom_duration:
		zoom_timer += delta
		var progress = zoom_timer / zoom_duration
		var new_zoom = lerp(zoom.x, target_zoom, progress)
		zoom = Vector2(new_zoom, new_zoom)
		zoom_changed.emit(new_zoom)

func _constrain_camera_bounds() -> void:
	var viewport_size = get_viewport_rect().size / zoom.x
	var min_x = map_bounds.position.x + viewport_size.x / 2
	var max_x = map_bounds.end.x - viewport_size.x / 2
	var min_y = map_bounds.position.y + viewport_size.y / 2
	var max_y = map_bounds.end.y - viewport_size.y / 2

	global_position.x = clamp(global_position.x, min_x, max_x)
	global_position.y = clamp(global_position.y, min_y, max_y)
```

### InputHandler (Protocol Commands)
```gdscript
# InputHandler.gd
class_name InputHandler
extends Node

@onready var command_system: ProtocolCommandSystem = get_tree().root.get_node("CommandNode/ProtocolCommandSystem")

var protocol_wheel_open: bool = false
var targeting_mode: bool = false
var current_protocol: String = ""

signal protocol_issued(protocol: String, target: Vector2)

func _input(event: InputEvent) -> void:
	# Protocol wheel (hold X)
	if Input.is_action_just_pressed("protocol_wheel"):
		protocol_wheel_open = true
		show_protocol_wheel()

	if Input.is_action_just_released("protocol_wheel"):
		protocol_wheel_open = false
		hide_protocol_wheel()

	# Quick-select protocols (D-Pad)
	if Input.is_action_just_pressed("protocol_1"):  # Swarm Rush
		issue_protocol("swarm_rush")

	if Input.is_action_just_pressed("protocol_2"):  # Rapid Replication
		issue_protocol("rapid_replication")

	if Input.is_action_just_pressed("protocol_3"):  # Scatter
		issue_protocol("scatter")

	if Input.is_action_just_pressed("protocol_4"):  # Defensive Formation
		issue_protocol("defensive_formation")

	if Input.is_action_just_pressed("protocol_5"):  # Assimilation Wave
		issue_protocol("assimilation_wave")

	# Targeting confirmation
	if targeting_mode and Input.is_action_just_pressed("confirm_command"):
		var cursor_pos = get_global_mouse_position()
		command_system.execute_protocol(current_protocol, cursor_pos)
		targeting_mode = false
		current_protocol = ""

func issue_protocol(protocol: String) -> void:
	current_protocol = protocol
	targeting_mode = true
	protocol_issued.emit(protocol, Vector2.ZERO)

func show_protocol_wheel() -> void:
	# TODO: Display radial menu centered on screen
	pass

func hide_protocol_wheel() -> void:
	# TODO: Hide radial menu
	pass
```

---

## Implementation Notes

- **Input Mapping:** Use Godot's InputMap system. Define actions like "pan_left", "protocol_wheel", etc.
- **Responsive Feel:** Ensure panning has **inertia** (gradual deceleration) for smooth camera movement.
- **Feedback:** Issue audio/visual cues for command confirmation (chime, unit pulse).
- **Accessibility:** Support both gamepad and keyboard/mouse. Allow remapping of controls.
- **Multiplayer Consistency:** Ensure camera panning doesn't desync players' views in co-op.

---

## Testing Checklist

- [ ] Panning is smooth and responsive.
- [ ] Zoom interpolation is gradual (no jarring jumps).
- [ ] Camera bounds prevent viewing outside facility.
- [ ] Unit selection (single, multiple, all) works correctly.
- [ ] Protocol commands issue and resolve correctly.
- [ ] Minimap is accurate and clickable.
- [ ] HUD elements update in real-time.
- [ ] Input conflicts are resolved (e.g., panning + zoom don't interfere).
- [ ] Multiplayer inputs sync correctly.

