## Minimap renderer: draws a small tactical overview in a corner of the screen.
## Shows ship triangles colored by team, flagship icon larger, map border.
class_name MinimapRenderer
extends RefCounted

const NC := preload("res://scripts/shared/naval_combat_constants.gd")

## Minimap panel size (pixels).
const MAP_SIZE: float = 200.0
## Margin from screen edge.
const MARGIN: float = 12.0
## Ship icon sizes.
const ICON_SIZE_NORMAL: float = 5.0
const ICON_SIZE_FLAGSHIP: float = 8.0
## Background / border colors.
const BG_COLOR: Color = Color(0.04, 0.06, 0.10, 0.82)
const BORDER_COLOR: Color = Color(0.30, 0.38, 0.50, 0.90)
const GRID_COLOR: Color = Color(0.15, 0.20, 0.30, 0.35)
## Team colors.
const PLAYER_COLOR: Color = Color(0.30, 0.55, 1.00, 0.95)
const PLAYER_FLAGSHIP_COLOR: Color = Color(0.45, 0.75, 1.00, 1.0)
const ENEMY_COLOR: Color = Color(0.90, 0.30, 0.20, 0.95)
const DEAD_COLOR: Color = Color(0.40, 0.35, 0.30, 0.45)
const ROUTED_COLOR: Color = Color(0.80, 0.70, 0.20, 0.70)

## World bounds (set once at init).
var world_width: float = 4000.0
var world_height: float = 4000.0


func configure(map_tiles_wide: int, map_tiles_high: int, units_per_tile: float) -> void:
	world_width = float(map_tiles_wide) * units_per_tile
	world_height = float(map_tiles_high) * units_per_tile


## Convert world coords to minimap pixel coords (relative to minimap top-left).
func _world_to_minimap(wx: float, wy: float) -> Vector2:
	var nx: float = clampf(wx / world_width, 0.0, 1.0)
	var ny: float = clampf(wy / world_height, 0.0, 1.0)
	return Vector2(nx * MAP_SIZE, ny * MAP_SIZE)


## Draw the minimap onto the arena's _draw() canvas.
## `canvas` = the Node2D calling draw_*.
## `vp` = viewport size.
## `players` = the _players array.
## `player_fleet_indices` = indices of player fleet ships.
## `enemy_indices` = indices of enemy fleet ships.
## `my_index` = the player's controlled ship index.
## `formation_lines` = optional array of {from: Vector2, to: Vector2, color: Color} for formation overlay.
func draw_minimap(
		canvas: CanvasItem,
		vp: Vector2,
		players: Array,
		player_fleet_indices: Array[int],
		enemy_indices: Array[int],
		my_index: int,
		formation_lines: Array[Dictionary] = []
	) -> void:
	# Position: bottom-left corner (above fleet order HUD).
	var panel_x: float = MARGIN
	var panel_y: float = vp.y - MAP_SIZE - MARGIN - 70.0  # 70px room for fleet order panel below

	# Background.
	canvas.draw_rect(Rect2(panel_x, panel_y, MAP_SIZE, MAP_SIZE), BG_COLOR)

	# Grid lines (quarter marks).
	for i in range(1, 4):
		var frac: float = float(i) / 4.0
		var gx: float = panel_x + MAP_SIZE * frac
		var gy: float = panel_y + MAP_SIZE * frac
		canvas.draw_line(Vector2(gx, panel_y), Vector2(gx, panel_y + MAP_SIZE), GRID_COLOR, 1.0)
		canvas.draw_line(Vector2(panel_x, gy), Vector2(panel_x + MAP_SIZE, gy), GRID_COLOR, 1.0)

	# Formation lines (drawn under ships).
	for fl in formation_lines:
		var from_mm: Vector2 = _world_to_minimap(fl["from_wx"], fl["from_wy"]) + Vector2(panel_x, panel_y)
		var to_mm: Vector2 = _world_to_minimap(fl["to_wx"], fl["to_wy"]) + Vector2(panel_x, panel_y)
		canvas.draw_line(from_mm, to_mm, fl.get("color", Color(0.4, 0.6, 0.8, 0.5)), 1.0, true)

	# Draw ships.
	# Enemy ships first (so player ships draw on top).
	for idx in enemy_indices:
		if idx < 0 or idx >= players.size():
			continue
		var p: Dictionary = players[idx]
		var alive: bool = bool(p.get("alive", true))
		var routed: bool = bool(p.get("is_routed", false))
		var col: Color = DEAD_COLOR if not alive else (ROUTED_COLOR if routed else ENEMY_COLOR)
		_draw_ship_icon(canvas, panel_x, panel_y, p, col, ICON_SIZE_NORMAL, not alive)

	# Player fleet ships.
	for idx in player_fleet_indices:
		if idx < 0 or idx >= players.size():
			continue
		var p: Dictionary = players[idx]
		var alive: bool = bool(p.get("alive", true))
		var is_flagship: bool = (idx == my_index)
		var col: Color
		var size: float
		if not alive:
			col = DEAD_COLOR
			size = ICON_SIZE_NORMAL
		elif is_flagship:
			col = PLAYER_FLAGSHIP_COLOR
			size = ICON_SIZE_FLAGSHIP
		else:
			col = PLAYER_COLOR
			size = ICON_SIZE_NORMAL
		_draw_ship_icon(canvas, panel_x, panel_y, p, col, size, not alive)

	# Border.
	canvas.draw_rect(Rect2(panel_x, panel_y, MAP_SIZE, MAP_SIZE), BORDER_COLOR, false, 1.5)

	# Label.
	var font: Font = ThemeDB.fallback_font
	canvas.draw_string(font, Vector2(panel_x + 4.0, panel_y - 3.0), "Tactical Map",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.70, 0.80, 0.85))


## Draw a single ship icon as a directional triangle.
func _draw_ship_icon(canvas: CanvasItem, px: float, py: float, ship: Dictionary,
		color: Color, size: float, is_dead: bool) -> void:
	var wx: float = float(ship.get("wx", 0.0))
	var wy: float = float(ship.get("wy", 0.0))
	var mm_pos: Vector2 = _world_to_minimap(wx, wy) + Vector2(px, py)

	if is_dead:
		# Dead ships: small X marker.
		var xs: float = 2.5
		canvas.draw_line(mm_pos - Vector2(xs, xs), mm_pos + Vector2(xs, xs), color, 1.0)
		canvas.draw_line(mm_pos - Vector2(xs, -xs), mm_pos + Vector2(xs, -xs), color, 1.0)
		return

	# Alive ships: directional triangle.
	var dir: Vector2 = ship.get("dir", Vector2.RIGHT)
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var perp: Vector2 = dir.rotated(PI * 0.5)

	var tip: Vector2 = mm_pos + dir * size
	var left: Vector2 = mm_pos - dir * size * 0.5 + perp * size * 0.5
	var right: Vector2 = mm_pos - dir * size * 0.5 - perp * size * 0.5

	canvas.draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
