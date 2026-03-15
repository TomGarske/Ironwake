extends CanvasLayer

# ---------------------------------------------------------------------------
# Scrolling rendered map background
# ---------------------------------------------------------------------------

const _SCROLL_SPEED: Vector2 = Vector2(34.0, 18.0)

var _time: float = 0.0
var _map_offset: Vector2 = Vector2.ZERO
var _map_drawer: Node2D

func _ready() -> void:
	layer = -1
	_map_drawer = Node2D.new()
	_map_drawer.name = "MapDrawer"
	_map_drawer.set_script(preload("res://scripts/screens/home_screen_background_drawer.gd"))
	add_child(_map_drawer)

func _process(delta: float) -> void:
	_time += delta
	_map_offset += _SCROLL_SPEED * delta
	if _map_drawer == null:
		return
	_map_drawer.time = _time
	_map_drawer.map_offset = _map_offset
	_map_drawer.viewport_size = get_viewport().get_visible_rect().size
	_map_drawer.queue_redraw()
