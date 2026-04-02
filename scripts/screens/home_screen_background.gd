extends CanvasLayer

const NC := preload("res://scripts/shared/naval_combat_constants.gd")
const MapProfile := preload("res://scripts/shared/ironwake_map_profile.gd")
const _OceanRenderer := preload("res://scripts/shared/ocean_renderer.gd")

## World-units per pixel (matches the arena's _TD_SCALE).
const _WORLD_SCALE: float = 4.0
## Slow pan speed in world units per second.
const _PAN_SPEED: Vector2 = Vector2(40.0, 20.0)

var _ocean_renderer: OceanRenderer = null
var _elapsed: float = 0.0
var _pan_world: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = -1
	_ocean_renderer = _OceanRenderer.new()
	_ocean_renderer.name = "OceanRenderer"
	add_child(_ocean_renderer)
	var map_size := Vector2(
		float(NC.MAP_TILES_WIDE) * NC.UNITS_PER_LOGIC_TILE,
		float(NC.MAP_TILES_HIGH) * NC.UNITS_PER_LOGIC_TILE
	)
	_ocean_renderer.configure(map_size, NC.UNITS_PER_LOGIC_TILE)
	var env: Dictionary = MapProfile.get_ocean_environment()
	_ocean_renderer.set_environment(
		env.get("wind_direction", Vector2(1.0, -0.25).normalized()),
		env.get("weather_preset", &"clear"),
		env.get("time_of_day_preset", &"day")
	)
	# Start panned to roughly the centre of the map.
	_pan_world = map_size * 0.5


func _process(delta: float) -> void:
	_elapsed += delta
	_pan_world += _PAN_SPEED * delta

	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Wrap so the pan stays within the map.
	var map_w: float = float(NC.MAP_TILES_WIDE) * NC.UNITS_PER_LOGIC_TILE
	var map_h: float = float(NC.MAP_TILES_HIGH) * NC.UNITS_PER_LOGIC_TILE
	_pan_world.x = fmod(_pan_world.x, map_w)
	_pan_world.y = fmod(_pan_world.y, map_h)

	# origin = screen-centre minus world-focus in screen pixels.
	var origin: Vector2 = vp * 0.5 - _pan_world * _WORLD_SCALE

	_ocean_renderer.update_view(vp, origin, 1.0, _WORLD_SCALE)
	_ocean_renderer.tick(delta)
