# REQ-04: Player Movement and Controls
**Chrimera: Bioforge Run**

## Overview
Player movement is **side-scrolling 2D platforming** with physics-based CharacterBody2D locomotion. Controls support both **keyboard/mouse** and **controller** input, with emphasis on controller (gamepad). This document defines input bindings, movement mechanics, physics parameters, and camera behavior.

---

## Input Map (Controller-Primary)

### Controller Bindings

| Action | Button | Function | Alternative (Keyboard) |
|--------|--------|----------|------------------------|
| **Move Left** | Left Stick X (Negative) | Character moves left | A / Left Arrow |
| **Move Right** | Left Stick X (Positive) | Character moves right | D / Right Arrow |
| **Jump** | A (SOUTH) | Initiate jump (variable-height hold) | Space |
| **Crouch/Slide** | B (EAST) | Enter crouch or activate slide | Ctrl |
| **Interact/Pickup** | Y (NORTH) | Interact with object (pickup, revive, open door) | E |
| **Melee** | X (WEST) | Desperation melee attack | Q |
| **Tool Use (Slot 1)** | RT (Right Trigger) | Activate tool in slot 1 | Mouse LMB |
| **Tool Use (Slot 2)** | LT (Left Trigger) | Activate tool in slot 2 | Mouse RMB |
| **Pause/Menu** | Start | Open pause menu | Escape |
| **Look Ahead** | Right Stick X | Shift camera lookahead direction | Not mapped |

### Input Setup in Godot
```gdscript
# In project.godcfg or InputMap
# Add or verify these inputs exist:
InputMap.add_action("move_left")
InputMap.add_action("move_right")
InputMap.add_action("jump")
InputMap.add_action("crouch")
InputMap.add_action("interact")
InputMap.add_action("melee")
InputMap.add_action("tool_slot_1")
InputMap.add_action("tool_slot_2")
InputMap.add_action("pause")

# Bind to controller buttons
InputMap.action_add_event("jump", InputEventJoypadButton.new())
InputMap.get_action_list("jump")[0].button_index = JOY_BUTTON_A
# ... repeat for all actions
```

---

## Movement Mechanics

### Horizontal Movement
```gdscript
class_name PlayerCharacter
extends CharacterBody2D

@export var max_speed: float = 8.0        # m/s (tiles/s)
@export var acceleration: float = 24.0    # m/s² (tiles/s²)
@export var deceleration: float = 20.0    # m/s² (tiles/s²)
@export var friction: float = 0.85

func _physics_process(delta: float):
    # Horizontal input
    var input_vector = Input.get_axis("move_left", "move_right")

    if input_vector != 0:
        # Accelerate in direction
        velocity.x = move_toward(velocity.x, input_vector * max_speed, acceleration * delta)
        # Face direction
        sprite.flip_h = input_vector < 0
    else:
        # Decelerate when no input
        velocity.x = move_toward(velocity.x, 0, deceleration * delta)

    velocity = move_and_slide(velocity)
```

### Vertical Movement (Jump)
```gdscript
@export var jump_force: float = 12.0         # m/s (upward velocity)
@export var gravity: float = 30.0            # m/s² (downward acceleration)
@export var max_fall_speed: float = 20.0     # m/s (terminal velocity)
@export var coyote_time: float = 0.1        # seconds after leaving ground
@export var jump_buffer: float = 0.15       # seconds before landing

var is_grounded: bool = false
var coyote_timer: float = 0.0
var jump_input_buffer: float = 0.0

func _physics_process(delta: float):
    # ... horizontal movement code ...

    # Check if grounded
    is_grounded = is_on_floor()

    # Coyote time: allow jump for 0.1s after leaving ground
    if is_grounded:
        coyote_timer = coyote_time
    else:
        coyote_timer -= delta

    # Jump buffer: if jump pressed up to 0.15s before landing, execute jump on landing
    if Input.is_action_just_pressed("jump"):
        jump_input_buffer = jump_buffer

    jump_input_buffer -= delta

    # Execute jump (coyote OR buffer condition)
    if (jump_input_buffer > 0.0 and coyote_timer > 0.0):
        velocity.y = -jump_force
        jump_input_buffer = 0.0
        coyote_timer = 0.0
        jump_audio.play()

    # Variable-height jump: reduced gravity while holding jump button
    if Input.is_action_pressed("jump") and velocity.y < 0:
        # Shorter falloff = higher gravity = longer fall = more momentum
        velocity.y += gravity * 0.6 * delta  # 60% gravity during ascent
    else:
        velocity.y += gravity * delta

    # Cap fall speed
    velocity.y = min(velocity.y, max_fall_speed)

    velocity = move_and_slide(velocity)
```

### Crouch and Slide

```gdscript
@export var crouch_hitbox_scale: float = 0.5  # reduce height to 50%
@export var slide_speed_boost: float = 1.3    # 30% speed boost
@export var slide_duration: float = 0.4       # seconds
@export var slide_cooldown: float = 1.0       # seconds between slides

var is_crouching: bool = false
var slide_timer: float = 0.0
var slide_cooldown_timer: float = 0.0

func _physics_process(delta: float):
    # ... jump/movement code ...

    # Slide mechanic
    if Input.is_action_just_pressed("crouch") and is_grounded and slide_cooldown_timer <= 0.0:
        slide_timer = slide_duration
        slide_cooldown_timer = slide_cooldown
        # Grant i-frames during slide
        invulnerable = true
        invulnerability_timer = slide_duration

    if slide_timer > 0.0:
        is_crouching = true
        velocity.x *= slide_speed_boost  # Boost current momentum
        collision_shape.scale.y = crouch_hitbox_scale
        slide_timer -= delta
    else:
        is_crouching = false
        collision_shape.scale.y = 1.0

    slide_cooldown_timer -= delta
```

---

## Physics Parameters

### CharacterBody2D Setup

| Parameter | Value | Purpose |
|-----------|-------|---------|
| **Velocity** | dynamic | Updated every frame by movement code. |
| **Gravity** | 30.0 | Standard downward acceleration. |
| **Terminal Velocity** | 20.0 | Max fall speed (prevents tunneling). |
| **Max Speed (horizontal)** | 8.0 | Movement speed cap. |
| **Acceleration** | 24.0 | Time to reach max speed from rest (~0.33s). |
| **Deceleration** | 20.0 | Time to stop from max speed (~0.4s). |
| **Friction** | 0.85 | Velocity damping coefficient (if used). |
| **Coyote Time** | 0.1s | Post-ground grace period for jump. |
| **Jump Buffer** | 0.15s | Pre-landing grace period for jump input. |

### Collision Shapes
- **Default Hitbox:** Rectangle (32px wide, 64px tall) for standing pose.
- **Crouched Hitbox:** Same width, 32px tall (50% height scale).
- **Interaction Range:** 64px (1m from center).
- **Melee Range:** 48px (1.5m from center).

---

## Animation States

PlayerCharacter uses an AnimationPlayer with the following named clips:

| State | Trigger | Animation | Duration |
|-------|---------|-----------|----------|
| **Idle** | No input, grounded | Breathing/standing pose | Looping |
| **Run** | Moving horizontally, grounded | Running animation | Looping (~0.6s per cycle) |
| **Jump** | Airborne, ascending | Jump start frame | 0.1s hold, then transitions to |
| **Fall** | Airborne, descending | Fall animation (legs straight) | Looping until landing |
| **Slide** | Crouch button pressed, grounded | Sliding pose (lowered body) | Tied to slide_timer |
| **Melee** | X button, melee cooldown check | Swing animation (arm extended) | 0.3s play, lock movement |
| **Downed** | Health <= 0, downed state | Knocked-down pose (lying) | Looping until revived/dead |
| **Using Tool** | Tool activation (context-dependent) | Tool-specific animation | Varies per tool (0.1s–1.0s) |

---

## Camera Behavior

### Side-Scroller Camera
```gdscript
class_name ChimeraCamera2D
extends Camera2D

@export var lookahead_distance: float = 2.0  # tiles ahead in facing direction
@export var follow_smoothing: float = 0.15  # easing factor (0–1)
@export var vertical_lock: bool = true      # prevent vertical scroll unless platform change
@export var zoom_min: float = 1.0           # solo player zoom
@export var zoom_max: float = 0.6           # 4-player zoom out

var target_position: Vector2
var all_players: Array[PlayerCharacter]
var player_spread: float = 0.0

func _ready():
    # Bind to player movement or let RunController add players
    player_moved.connect(update_camera)

func _process(delta: float):
    # Calculate bounds of all active players
    var player_bounds = Rect2()
    for player in all_players:
        if player.is_alive:
            player_bounds = player_bounds.expand(player.global_position)

    # Lookahead in average facing direction
    var avg_facing = 0.0
    for player in all_players:
        avg_facing += -1.0 if player.sprite.flip_h else 1.0
    avg_facing /= all_players.size()

    target_position = player_bounds.get_center() + Vector2(avg_facing * lookahead_distance, 0)

    # Smooth camera follow
    global_position = global_position.lerp(target_position, follow_smoothing)

    # Calculate zoom based on player spread
    player_spread = player_bounds.size.x
    var target_zoom = lerp(zoom_min, zoom_max, clamp(player_spread / 12.0, 0.0, 1.0))
    zoom = zoom.lerp(Vector2(target_zoom, target_zoom), 0.1)

    # Vertical lock (only adjust Y if platform change detected)
    if vertical_lock:
        global_position.y = player_bounds.get_center().y
```

### Multiplayer Camera Behavior
- **Single Player:** Camera centered on player with lookahead.
- **2–4 Players:** Camera frames all players (zoom out as spread increases).
- **Max Spread:** If players are >12 tiles apart, zoom out to 0.6x (60% of screen size).
- **Separation Warning:** If distance between players exceeds 15 tiles, a visual warning appears (red vignette) and a **soft pull** occurs (non-player gets +2m/s toward group for 2s).

---

## Cooperative Proximity Mechanics

### Proximity Bonus
When players are within **3m (6 tiles)** of each other:
- **Movement Speed:** +10% (8.0 → 8.8 m/s)
- **Tool Cooldowns:** -10% (5s cooldown → 4.5s)
- **Revive Duration:** Downed timer extends +2s (8s → 10s)

```gdscript
func _process(delta: float):
    var nearby_allies = []
    for player in all_players:
        if player != self and not player.is_dead:
            var distance = global_position.distance_to(player.global_position)
            if distance <= 6.0:  # 6 tiles = 3m
                nearby_allies.append(player)

    if nearby_allies.size() > 0:
        max_speed *= 1.1
        # Apply cooldown reduction to active tools
        for tool in [tool_slot_manager.slot_1, tool_slot_manager.slot_2]:
            if tool:
                tool.cooldown_seconds *= 0.9
```

### Cooperative Proximity Separation Warning
If any two players exceed **15 tiles (7.5m)** separation:
1. **Visual:** Red vignette overlay fades in on separated player's screen.
2. **Audio:** Warning chirp (facility alarm).
3. **Mechanic:** Separated player gains +2 m/s toward nearest ally for 2s (soft pull, not forced).

---

## Input Blocking and State Interaction

### Input Allowed By State

| State | Move | Jump | Crouch | Interact | Melee | Tool | Notes |
|-------|------|------|--------|----------|-------|------|-------|
| Idle | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | Normal. |
| Running | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | No interact/melee while moving. |
| Airborne | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | Can use tools mid-air. |
| Melee | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | Locked during swing (0.3s). |
| Downed | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | Cannot act while downed. |
| Sliding | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | Momentum-driven; jump out of slide. |

---

## Platform Edge Cling (Optional Deferred Feature)

```gdscript
# Pseudocode for ledge grab (not MVP)
@export var wall_cling_max_duration: float = 3.0
@export var wall_cling_drain: float = 20.0  # stamina/sec
var wall_cling_timer: float = 0.0

func check_wall_cling():
    # If airborne, moving toward wall, and wall present within 1m:
    var wall_check = get_world_2d().direct_space_state.intersect_ray(
        global_position,
        global_position + Vector2(2.0 if not sprite.flip_h else -2.0, 0)
    )

    if wall_check and velocity.y > 0 and Input.get_axis("move_left", "move_right") != 0:
        # Enter cling state
        velocity.y = 0  # Stop falling
        wall_cling_timer = wall_cling_max_duration
        # Stamina drain
        stamina -= wall_cling_drain * delta
```

---

## Testing Checkpoints

### Phase 1: Foundation (Movement Only)
- [ ] Left/right movement responds to input with correct acceleration/deceleration.
- [ ] Jump has variable height based on hold duration.
- [ ] Coyote time allows jump within 0.1s of leaving ground.
- [ ] Jump buffer allows jump input 0.15s before landing.
- [ ] Slide reduces hitbox, grants i-frames, has 1s cooldown.
- [ ] Crouch animation plays and collision height reduces.

### Phase 2: Animation and Input Responsiveness
- [ ] Idle/Run/Jump/Fall animations play correctly.
- [ ] Slide animation locks player in place briefly.
- [ ] Melee animation plays, locking movement for 0.3s.
- [ ] Tool use animations trigger (if tool has custom animation).

### Phase 3: Camera and Multiplayer
- [ ] Camera follows single player with lookahead.
- [ ] Camera frames 2 players, zooming out as they separate.
- [ ] Camera zooms to 0.6x when players are >12 tiles apart.
- [ ] Separation warning (red vignette) appears at >15 tiles.
- [ ] Soft pull activates and moves separated player toward group.

### Phase 4: Proximity Bonuses
- [ ] Within 3m: speed boost +10%, cooldown reduction -10% apply.
- [ ] Downed timer extends +2s when near ally.

---

## Implementation Notes

1. **CharacterBody2D.move_and_slide():** Handles collision response automatically; just update velocity each frame.
2. **Input Buffering:** Jump and interact inputs are buffered (0.15s and 0.2s respectively) to feel responsive despite input lag.
3. **Axis Deadzone:** Set to 0.2 on controller left stick to avoid drift.
4. **Animation Blending:** Use AnimationPlayer with One-Shot or Looping tracks; blend between states using `play()` or `set_animation()`.
5. **Multiplayer Camera:** RunController should maintain `all_players` array and pass to ChimeraCamera2D on peer join/leave.

---

## Next Steps
- **REQ-05:** Roguelike progression (meta-upgrades, archetype bonuses affecting movement).
- **REQ-06:** CRISPR entity AI (movement, detection, attack patterns).
