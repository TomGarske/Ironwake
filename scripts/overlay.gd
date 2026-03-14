extends Node2D

## Rendered above units (z_index = 1 in scene).
## TacticalMap sets the public vars and calls queue_redraw() on state changes.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# State (set by TacticalMap)
# ---------------------------------------------------------------------------
var selected_unit: Node = null
var valid_move_tiles: Array = []       # Array[Vector2i]
var valid_attack_positions: Array = [] # Array[Vector2i]

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
func _draw() -> void:
	_draw_move_highlights()
	_draw_attack_highlights()
	_draw_selection_highlight()
	_draw_grid_lines()

func _draw_move_highlights() -> void:
	for tile: Vector2i in valid_move_tiles:
		draw_rect(
			Rect2(
				tile.x * GameConstants.TILE_SIZE,
				tile.y * GameConstants.TILE_SIZE,
				GameConstants.TILE_SIZE,
				GameConstants.TILE_SIZE
			),
			Color(0.2, 0.6, 1.0, 0.35)
		)
		draw_rect(
			Rect2(
				tile.x * GameConstants.TILE_SIZE,
				tile.y * GameConstants.TILE_SIZE,
				GameConstants.TILE_SIZE,
				GameConstants.TILE_SIZE
			),
			Color(0.3, 0.7, 1.0), false, 1.5
		)

func _draw_attack_highlights() -> void:
	for pos: Vector2i in valid_attack_positions:
		draw_rect(
			Rect2(
				pos.x * GameConstants.TILE_SIZE,
				pos.y * GameConstants.TILE_SIZE,
				GameConstants.TILE_SIZE,
				GameConstants.TILE_SIZE
			),
			Color(1.0, 0.15, 0.15, 0.45)
		)
		draw_rect(
			Rect2(
				pos.x * GameConstants.TILE_SIZE,
				pos.y * GameConstants.TILE_SIZE,
				GameConstants.TILE_SIZE,
				GameConstants.TILE_SIZE
			),
			Color(1.0, 0.2, 0.2), false, 1.5
		)

func _draw_selection_highlight() -> void:
	if selected_unit == null:
		return
	var pos: Vector2i = selected_unit.grid_pos
	draw_rect(
		Rect2(
			pos.x * GameConstants.TILE_SIZE,
			pos.y * GameConstants.TILE_SIZE,
			GameConstants.TILE_SIZE,
			GameConstants.TILE_SIZE
		),
		Color(1.0, 0.95, 0.2, 0.4)
	)
	draw_rect(
		Rect2(
			pos.x * GameConstants.TILE_SIZE,
			pos.y * GameConstants.TILE_SIZE,
			GameConstants.TILE_SIZE,
			GameConstants.TILE_SIZE
		),
		Color.YELLOW, false, 3.0
	)

func _draw_grid_lines() -> void:
	var line_color := Color(0.0, 0.0, 0.0, 0.45)
	for x in range(GameConstants.GRID_WIDTH + 1):
		draw_line(
			Vector2(x * GameConstants.TILE_SIZE, 0),
			Vector2(x * GameConstants.TILE_SIZE, GameConstants.GRID_HEIGHT * GameConstants.TILE_SIZE),
			line_color, 1.0
		)
	for y in range(GameConstants.GRID_HEIGHT + 1):
		draw_line(
			Vector2(0, y * GameConstants.TILE_SIZE),
			Vector2(GameConstants.GRID_WIDTH * GameConstants.TILE_SIZE, y * GameConstants.TILE_SIZE),
			line_color, 1.0
		)
