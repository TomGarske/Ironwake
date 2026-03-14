extends Node2D

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const TILE_SIZE: int = 64
const UNIT_DRAW_SIZE: int = 52  # Slightly inset from tile edge
const TEAM_COLORS: Array = [Color.CORNFLOWER_BLUE, Color.TOMATO]

# ---------------------------------------------------------------------------
# Exported fields (set at spawn time by TacticalMap)
# ---------------------------------------------------------------------------
@export var max_health: int = 3
@export var move_range: int = 3

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------
var unit_id: int = 0
var team: int = 0
var grid_pos: Vector2i = Vector2i.ZERO
var health: int = 0

var has_moved: bool = false
var has_attacked: bool = false

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal unit_died(unit_id: int)

# ---------------------------------------------------------------------------
# Visual
# ---------------------------------------------------------------------------
func _draw() -> void:
	var color: Color = TEAM_COLORS[team] if team < TEAM_COLORS.size() else Color.GRAY
	var half: float = UNIT_DRAW_SIZE / 2.0
	draw_rect(Rect2(-half, -half, UNIT_DRAW_SIZE, UNIT_DRAW_SIZE), color)
	draw_rect(Rect2(-half, -half, UNIT_DRAW_SIZE, UNIT_DRAW_SIZE), Color.WHITE, false, 2.0)

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func setup(id: int, start_pos: Vector2i, team_id: int) -> void:
	unit_id = id
	team = team_id
	health = max_health
	_set_grid_pos(start_pos)
	_update_health_label()
	queue_redraw()

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
func move_to(target_pos: Vector2i) -> void:
	_set_grid_pos(target_pos)
	has_moved = true

func take_damage(amount: int) -> void:
	health -= amount
	_update_health_label()
	print("[Unit %d] Took %d damage. HP: %d/%d" % [unit_id, amount, health, max_health])
	if health <= 0:
		unit_died.emit(unit_id)
		queue_free()

func reset_actions() -> void:
	has_moved = false
	has_attacked = false

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------
func can_move_to(target: Vector2i) -> bool:
	if has_moved:
		return false
	var dist: int = abs(target.x - grid_pos.x) + abs(target.y - grid_pos.y)
	return dist > 0 and dist <= move_range

func can_attack(target_pos: Vector2i) -> bool:
	if has_attacked:
		return false
	# Melee range: Manhattan distance of 1
	var dist: int = abs(target_pos.x - grid_pos.x) + abs(target_pos.y - grid_pos.y)
	return dist == 1

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------
func _set_grid_pos(pos: Vector2i) -> void:
	grid_pos = pos
	position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2.0, pos.y * TILE_SIZE + TILE_SIZE / 2.0)

func _update_health_label() -> void:
	var label: Label = get_node_or_null("HealthLabel")
	if label:
		label.text = "%d/%d" % [max(health, 0), max_health]
