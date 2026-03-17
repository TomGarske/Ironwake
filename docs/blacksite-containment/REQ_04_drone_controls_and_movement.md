# REQ_04: Drone Controls and Movement
**Input, Physics, and Camera**

## Movement Philosophy

Drones **hover freely** without gravity. They respond instantly to input and move omnidirectionally in 3D space. The control scheme emphasizes responsive, predictable motion suitable for aerial combat positioning.

## Input Mapping

**Controller (Primary):**

| Action | Input | Function |
|--------|-------|----------|
| Move Horizontal | Left Stick (X, Y) | Horizontal movement in world space (not camera-relative) |
| Move Vertical | Left Stick (click) + LT or RT | Alt vertical control (up/down altitude); or separate key binding |
| Look / Aim | Right Stick (X, Y) | Camera pan and laser/orbital strike aiming |
| Charge Laser | RT (hold) | Hold to charge laser; release to fire |
| Burst Speed | LB (press) | Instant dash in movement direction |
| Orbital Strike | RB (press) | Activate targeting mode; press again to call |
| Framerate Control | LT (press) | Toggle slow-motion perception |
| Pause / Menu | Start / Menu Button | Pause game (host-side decision) |
| Communication (future) | Y or D-Pad Up | Quick-chat callouts (optional) |

**Keyboard (Secondary / Testing):**

| Action | Input | Function |
|--------|-------|----------|
| Move Forward | W | Forward movement |
| Move Backward | S | Backward movement |
| Move Left | A | Leftward movement |
| Move Right | D | Rightward movement |
| Move Up | Space | Altitude up |
| Move Down | Ctrl | Altitude down |
| Look Right | Arrow Right | Camera pan right |
| Look Left | Arrow Left | Camera pan left |
| Charge Laser | Mouse / Click | Hold to charge |
| Other Abilities | 1, 2, 3, 4 | Keybinds for testing ability triggers |

---

## Drone Physics Model

### Coordinate System
- **World Space**: Fixed global axes (Y = altitude, X/Z = horizontal plane).
- **Drone Reference**: Each drone maintains a local facing direction (forward vector).
- **Movement Input**: Left stick translates directly to horizontal velocity without camera influence.

### Hovering (No Gravity)

```gdscript
# DroneController.gd (excerpt)
class_name DroneController
extends CharacterBody3D

const MOVE_SPEED: float = 20.0  # m/s horizontal
const VERTICAL_SPEED: float = 15.0  # m/s altitude
const ACCEL_TIME: float = 0.2  # seconds to reach target speed
const FRICTION: float = 0.85  # velocity damping when no input
const SOFT_REPULSION_RADIUS: float = 2.5  # meters from other drones

var current_velocity: Vector3 = Vector3.ZERO
var input_velocity: Vector3 = Vector3.ZERO

func _physics_process(delta: float) -> void:
	# Read input
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var vertical_input = 0.0
	if Input.is_action_pressed("move_up"):
		vertical_input += 1.0
	if Input.is_action_pressed("move_down"):
		vertical_input -= 1.0

	# Normalize input to prevent faster diagonal movement
	input_dir = input_dir.normalized()

	# Convert input to world velocity target
	var target_velocity = Vector3(input_dir.x, vertical_input, input_dir.y) * MOVE_SPEED
	target_velocity.y *= VERTICAL_SPEED / MOVE_SPEED  # Altitude scale factor

	# Smoothly interpolate toward target velocity (lerp simulation)
	current_velocity = current_velocity.lerp(target_velocity, 1.0 - pow(FRICTION, delta / ACCEL_TIME))

	# Apply collision (soft repulsion from other drones)
	apply_soft_repulsion()

	# Physics move (no gravity applied)
	velocity = current_velocity
	move_and_slide()

	# Sync position to network (delta compression)
	if is_multiplayer_authority():
		_sync_position_to_network.call_deferred()

func apply_soft_repulsion() -> void:
	# Query nearby drones; repel if too close
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D()
	query.shape = SphereShape3D.new()
	query.shape.radius = SOFT_REPULSION_RADIUS
	query.transform.origin = global_position
	var results = space_state.intersect_shape(query)

	var repulsion = Vector3.ZERO
	for result in results:
		if result.collider.is_in_group("drone") and result.collider != self:
			var diff = global_position - result.collider.global_position
			repulsion += diff.normalized() * 0.5

	current_velocity += repulsion

@rpc("unreliable")
func _sync_position_to_network() -> void:
	# Host sends position to clients
	pass
```

### Speed Characteristics

| Condition | Speed | Acceleration | Notes |
|-----------|-------|--------------|-------|
| Normal Cruise | 20 m/s | 0.2s to full | Responsive, precise |
| Burst Speed (Dash) | 85 m/s (for 0.3s) | Instant | See REQ_03; interrupts charge |
| Vertical (Altitude) | 15 m/s | 0.2s to full | Slightly slower than horizontal |
| Stationary (no input) | 0 m/s | 0.4s decel | Momentum/friction model |

---

## Camera System

### Camera Type: Isometric Top-Down Follow

**Overview**: Fixed offset follow camera positioned above and behind each drone. The camera **does not rotate with player input**; it maintains a fixed angle, providing consistent directional orientation.

```gdscript
# DroneCamera.gd
class_name DroneCamera
extends Camera3D

@onready var drone: CharacterBody3D = get_parent()

const CAMERA_DISTANCE: float = 12.0  # meters behind drone
const CAMERA_HEIGHT: float = 8.0  # meters above drone
const CAMERA_ANGLE: float = -45.0  # degrees (pitch down)
const FOLLOW_SMOOTHING: float = 0.1  # interpolation factor

var target_offset: Vector3

func _ready() -> void:
	target_offset = Vector3(0, CAMERA_HEIGHT, CAMERA_DISTANCE)
	global_position = drone.global_position + target_offset

func _process(delta: float) -> void:
	# Smoothly follow drone position
	var target_position = drone.global_position + target_offset
	global_position = global_position.lerp(target_position, FOLLOW_SMOOTHING)

	# Always look at drone (with slight up offset for better visibility)
	look_at(drone.global_position + Vector3(0, 1.5, 0), Vector3.UP)
```

**Camera Offset**:
- Position: 12 meters behind, 8 meters above drone center
- Angle: -45° pitch (isometric-style overhead view)
- Field of View: 70° (standard, tunable per device/preference)

**Right Stick (Camera Control)**:
- Right stick X/Y adjusts **laser/orbital aim direction** (not camera position).
- The aim direction is decoupled from the camera; laser fires in the aimed direction, not camera-forward.

---

## Collision Behavior

### Soft Repulsion
- **Mechanism**: When drones get within 2.5 meters of each other, a repulsive force pushes them apart gently.
- **Strength**: Low magnitude (0.5 units per collision frame) to avoid harsh clipping.
- **Result**: Drones naturally spread out without hard collision blocking.

### World Geometry
- Drones collide with walls, floors, and obstacles as defined by the arena geometry (StaticBody3D).
- Use standard Godot collision groups to distinguish drone-passable and drone-blocked areas.

### No Gravity Well
- Drones do not fall if altitude is set high. They hover indefinitely at current altitude unless player input changes it.

---

## Idle Animation

When a drone is stationary (velocity ~0), apply subtle hovering animation:

```gdscript
# DroneIdleAnimation.gd
class_name DroneIdleAnimation
extends Node3D

@onready var drone: CharacterBody3D = get_parent()

const BOB_SPEED: float = 2.0  # Hz
const BOB_AMOUNT: float = 0.3  # meters

var idle_time: float = 0.0
var base_y: float = 0.0

func _ready() -> void:
	base_y = drone.global_position.y

func _process(delta: float) -> void:
	if drone.velocity.length() < 0.5:  # Idle threshold
		idle_time += delta
		var bob_offset = sin(idle_time * BOB_SPEED * TAU) * BOB_AMOUNT
		drone.global_position.y = base_y + bob_offset
	else:
		idle_time = 0.0
		base_y = drone.global_position.y
```

---

## Network Synchronization

**Movement Authority**:
- Each drone is authoritative over its own movement input (local input processing).
- The drone's position is continuously synced to other players via RPC.

**Sync Rate**:
- Position updates sent every 2 frames (~33ms at 60fps) via `_sync_position_to_network()` RPC.
- High-frequency small corrections use delta compression (only send position if it differs significantly from last sent position).

**Interpolation on Remote Drones**:
- Remote drones interpolate position between sync points for smooth motion.

```gdscript
# Remote drone interpolation (on receiving clients)
func _apply_remote_position(new_pos: Vector3, delta_time: float) -> void:
	target_remote_position = new_pos
	interpolation_time = delta_time

func _process(delta: float) -> void:
	if is_remote:
		interpolation_time -= delta
		if interpolation_time > 0:
			global_position = global_position.lerp(target_remote_position, 1.0 - interpolation_time / SYNC_INTERVAL)
```

---

## Input Responsiveness

**Immediate Response**: Movement input results in visible velocity change within one frame (no input buffering delay).

**Charge Laser Interrupt**:
- If burst speed (LB) is pressed while charge laser (RT) is held, the charge is **instantly canceled** and burst activates.
- The player can immediately re-press RT after burst completes to restart charging.

**Edge Cases**:
- **Rapid Input**: If multiple ability inputs occur in the same frame, prioritize in order: Burst > Orbital > Framerate Control > Charge (by input processing order).
- **AFK Detection**: Monitor input history; if no movement or ability input for 30 seconds, mark as AFK (see REQ_02).

---

## Platform-Specific Notes

### PC (Keyboard/Mouse)
- Full analog stick emulation via WASD for movement.
- Mouse look can optionally control aim direction via right-click drag (future enhancement).

### Console (Controller)
- Dual-stick layout (left = move, right = aim/look).
- Haptic feedback on LB burst (controller rumble during dash).
- Trigger analog values used for RT charge laser (variable pressure sensitivity).

### Mobile (if supported in future)
- Touch-drag on left side = movement.
- Touch-drag on right side = aim.
- Tap buttons on-screen for abilities.

---

## Testing Checklist

- [ ] Drone responds instantly to left stick input; no lag or dead zone issues.
- [ ] Vertical movement (up/down) feels consistent with horizontal speed.
- [ ] Soft repulsion prevents drone clipping; drones naturally separate.
- [ ] Camera follow is smooth and never loses target.
- [ ] Overheat (charge laser > 1.0s) correctly interrupts charge and applies cooldown.
- [ ] Burst speed dash distance is exactly 15 meters; invincibility window is 0.3s.
- [ ] Remote drones interpolate smoothly; no teleporting or jittering.
- [ ] Aerial collisions with arena geometry behave predictably (no getting stuck).

---

**Implementation Notes:**
- Use Godot 4's `CharacterBody3D.move_and_slide()` for collision. No rigid body simulation needed.
- Manually apply velocity each frame; CharacterBody3D handles collision pushing.
- Camera should be a separate Camera3D node child of the arena (not drone), to avoid camera clipping into drone geometry.
- Test all three movement profiles (1 player, 4 players, 8 players) to ensure scaling is appropriate.
