extends Node2D
class_name OceanRenderer

const OCEAN_SURFACE_SHADER := preload("res://scripts/shared/ocean_surface.gdshader")

const _WAKE_SAMPLE_INTERVAL: float = 0.05
const _WAKE_SAMPLE_MIN_DIST: float = 7.0
const _WAKE_SAMPLE_LIFETIME: float = 2.6
const _WAKE_MAX_SAMPLES: int = 14
const _FOAM_SPEED_THRESHOLD: float = 0.12

class OceanSurfaceLayer:
	extends Node2D

	var renderer = null

	func _draw() -> void:
		if renderer == null or renderer._viewport_size.x <= 0.0 or renderer._viewport_size.y <= 0.0:
			return
		draw_rect(Rect2(Vector2.ZERO, renderer._viewport_size), Color.WHITE)

class OceanEffectLayer:
	extends Node2D

	var renderer = null

	func _draw() -> void:
		if renderer == null:
			return
		renderer._draw_impacts(self)
		renderer._draw_wakes(self)

var _ocean_material: ShaderMaterial = null
var _surface_layer: OceanSurfaceLayer = null
var _effect_layer: OceanEffectLayer = null
var _map_size_world: Vector2 = Vector2(8000.0, 8000.0)
var _units_per_tile: float = 10.0
var _viewport_size: Vector2 = Vector2.ZERO
var _origin: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _world_scale: float = 1.0
var _wind_direction: Vector2 = Vector2(1.0, -0.25).normalized()
var _weather_preset: StringName = &"clear"
var _time_of_day_preset: StringName = &"day"
var _elapsed: float = 0.0
var _ship_states: Array = []
var _water_impacts: Array = []
var _wake_tracks: Dictionary = {}

func _ready() -> void:
	show_behind_parent = true
	z_as_relative = false
	z_index = -100
	_ocean_material = ShaderMaterial.new()
	_ocean_material.shader = OCEAN_SURFACE_SHADER
	_surface_layer = OceanSurfaceLayer.new()
	_surface_layer.name = "OceanSurfaceLayer"
	_surface_layer.renderer = self
	_surface_layer.show_behind_parent = true
	_surface_layer.z_as_relative = false
	_surface_layer.z_index = -100
	_surface_layer.material = _ocean_material
	add_child(_surface_layer)
	_effect_layer = OceanEffectLayer.new()
	_effect_layer.name = "OceanEffectLayer"
	_effect_layer.renderer = self
	_effect_layer.show_behind_parent = true
	_effect_layer.z_as_relative = false
	_effect_layer.z_index = -99
	add_child(_effect_layer)
	_apply_environment_uniforms()

func configure(map_size_world: Vector2, units_per_tile: float) -> void:
	_map_size_world = map_size_world
	_units_per_tile = maxf(units_per_tile, 0.001)
	if _ocean_material != null:
		_ocean_material.set_shader_parameter("u_map_size_world", _map_size_world)

func set_environment(wind_direction: Vector2, weather_preset: StringName, time_of_day_preset: StringName) -> void:
	if wind_direction.length_squared() > 0.0001:
		_wind_direction = wind_direction.normalized()
	_weather_preset = weather_preset
	_time_of_day_preset = time_of_day_preset
	_apply_environment_uniforms()

func set_ship_states(states: Array) -> void:
	_ship_states = states

func set_water_impacts(events: Array) -> void:
	_water_impacts = events

func update_view(viewport_size: Vector2, origin: Vector2, zoom: float, world_scale: float) -> void:
	_viewport_size = viewport_size
	_origin = origin
	_zoom = zoom
	_world_scale = maxf(world_scale, 0.001)
	if _ocean_material == null:
		return
	_ocean_material.set_shader_parameter("u_viewport_size", _viewport_size)
	_ocean_material.set_shader_parameter("u_origin", _origin)
	_ocean_material.set_shader_parameter("u_world_scale", _world_scale)

func tick(delta: float) -> void:
	_elapsed += delta
	if _ocean_material != null:
		_ocean_material.set_shader_parameter("u_time", _elapsed)
	_update_wake_tracks(delta)
	if _surface_layer != null:
		_surface_layer.queue_redraw()
	if _effect_layer != null:
		_effect_layer.queue_redraw()

func _apply_environment_uniforms() -> void:
	if _ocean_material == null:
		return
	var palette: Dictionary = _palette_for(_time_of_day_preset, _weather_preset)
	_ocean_material.set_shader_parameter("u_wind_dir", _wind_direction)
	_ocean_material.set_shader_parameter("u_sky_color", palette.get("sky", Color(0.40, 0.58, 0.78, 1.0)))
	_ocean_material.set_shader_parameter("u_shallow_color", palette.get("shallow", Color(0.18, 0.44, 0.64, 1.0)))
	_ocean_material.set_shader_parameter("u_deep_color", palette.get("deep", Color(0.06, 0.22, 0.42, 1.0)))
	_ocean_material.set_shader_parameter("u_swell_color", palette.get("swell", Color(0.08, 0.18, 0.24, 0.18)))
	_ocean_material.set_shader_parameter("u_ripple_color", palette.get("ripple", Color(0.74, 0.90, 0.98, 0.12)))
	_ocean_material.set_shader_parameter("u_map_size_world", _map_size_world)

func _palette_for(time_of_day_preset: StringName, weather_preset: StringName) -> Dictionary:
	var palette: Dictionary = {
		"sky": Color(0.40, 0.58, 0.78, 1.0),
		"shallow": Color(0.18, 0.44, 0.64, 1.0),
		"deep": Color(0.06, 0.22, 0.42, 1.0),
		"swell": Color(0.08, 0.18, 0.24, 0.18),
		"ripple": Color(0.74, 0.90, 0.98, 0.12),
	}
	match time_of_day_preset:
		&"dusk":
			palette["sky"] = Color(0.68, 0.48, 0.52, 1.0)
			palette["shallow"] = Color(0.20, 0.34, 0.52, 1.0)
			palette["deep"] = Color(0.05, 0.14, 0.28, 1.0)
			palette["ripple"] = Color(0.96, 0.72, 0.60, 0.12)
		&"storm":
			palette["sky"] = Color(0.26, 0.32, 0.40, 1.0)
			palette["shallow"] = Color(0.15, 0.31, 0.44, 1.0)
			palette["deep"] = Color(0.05, 0.12, 0.20, 1.0)
			palette["swell"] = Color(0.04, 0.10, 0.16, 0.24)
			palette["ripple"] = Color(0.84, 0.92, 0.96, 0.08)
	if weather_preset == &"overcast":
		palette["sky"] = Color(0.34, 0.42, 0.50, 1.0)
		palette["swell"] = Color(0.06, 0.14, 0.18, 0.22)
	return palette

func _update_wake_tracks(delta: float) -> void:
	var active_ids: Dictionary = {}
	for state in _ship_states:
		var ship_id: String = str(state.get("id", ""))
		if ship_id.is_empty():
			continue
		active_ids[ship_id] = true
		var alive: bool = bool(state.get("alive", true))
		var track: Dictionary = _wake_tracks.get(ship_id, {"samples": [], "sample_timer": 0.0})
		var samples: Array = track.get("samples", [])
		for i in range(samples.size() - 1, -1, -1):
			var sample: Dictionary = samples[i]
			sample["age"] = float(sample.get("age", 0.0)) + delta
			if float(sample.get("age", 0.0)) >= _WAKE_SAMPLE_LIFETIME:
				samples.remove_at(i)
			else:
				samples[i] = sample
		var sample_timer: float = float(track.get("sample_timer", 0.0)) - delta
		if alive:
			var stern_world: Vector2 = state.get("stern_world", Vector2.ZERO)
			var speed_ratio: float = clampf(float(state.get("speed_ratio", 0.0)), 0.0, 1.2)
			var turn_amount: float = clampf(float(state.get("turn_amount", 0.0)), 0.0, 1.0)
			if speed_ratio > 0.02:
				var should_sample: bool = sample_timer <= 0.0
				if not samples.is_empty():
					var newest: Dictionary = samples[0]
					if stern_world.distance_to(newest.get("world", stern_world)) < _WAKE_SAMPLE_MIN_DIST:
						should_sample = false
				if should_sample:
					samples.push_front({
						"world": stern_world,
						"age": 0.0,
						"width": lerpf(7.0, 24.0, clampf(speed_ratio, 0.0, 1.0)) + turn_amount * 10.0,
						"foam": maxf(0.0, speed_ratio - _FOAM_SPEED_THRESHOLD) * 0.9 + turn_amount * 0.7,
						"heading": state.get("heading", Vector2.RIGHT),
						"turn_amount": turn_amount,
					})
					if samples.size() > _WAKE_MAX_SAMPLES:
						samples.resize(_WAKE_MAX_SAMPLES)
					sample_timer = _WAKE_SAMPLE_INTERVAL
			else:
				sample_timer = 0.0
		track["samples"] = samples
		track["sample_timer"] = sample_timer
		if not samples.is_empty() or alive:
			_wake_tracks[ship_id] = track
		else:
			_wake_tracks.erase(ship_id)
	for ship_id in _wake_tracks.keys().duplicate():
		if active_ids.has(ship_id):
			continue
		var track: Dictionary = _wake_tracks[ship_id]
		var samples: Array = track.get("samples", [])
		for i in range(samples.size() - 1, -1, -1):
			var sample: Dictionary = samples[i]
			sample["age"] = float(sample.get("age", 0.0)) + delta
			if float(sample.get("age", 0.0)) >= _WAKE_SAMPLE_LIFETIME:
				samples.remove_at(i)
			else:
				samples[i] = sample
		if samples.is_empty():
			_wake_tracks.erase(ship_id)
		else:
			track["samples"] = samples
			_wake_tracks[ship_id] = track

func _draw_wakes(canvas: CanvasItem) -> void:
	for track in _wake_tracks.values():
		var samples: Array = track.get("samples", [])
		if samples.size() < 2:
			continue
		for i in range(samples.size() - 1):
			var newer: Dictionary = samples[i]
			var older: Dictionary = samples[i + 1]
			var a_world: Vector2 = newer.get("world", Vector2.ZERO)
			var b_world: Vector2 = older.get("world", Vector2.ZERO)
			var a: Vector2 = _world_to_screen(a_world)
			var b: Vector2 = _world_to_screen(b_world)
			var seg: Vector2 = a - b
			if seg.length_squared() < 0.25:
				continue
			var side: Vector2 = Vector2(-seg.y, seg.x).normalized()
			var newer_t: float = clampf(1.0 - float(newer.get("age", 0.0)) / _WAKE_SAMPLE_LIFETIME, 0.0, 1.0)
			var older_t: float = clampf(1.0 - float(older.get("age", 0.0)) / _WAKE_SAMPLE_LIFETIME, 0.0, 1.0)
			var base_width_a: float = float(newer.get("width", 8.0)) * _zoom
			var base_width_b: float = float(older.get("width", 8.0)) * _zoom
			var wake_alpha: float = 0.11 * minf(newer_t, older_t)
			var foam_alpha: float = 0.18 * minf(newer_t, older_t)
			var outer := PackedVector2Array([
				a + side * base_width_a,
				a - side * base_width_a,
				b - side * base_width_b,
				b + side * base_width_b,
			])
			canvas.draw_colored_polygon(outer, Color(0.78, 0.90, 0.98, wake_alpha))
			var inner := PackedVector2Array([
				a + side * base_width_a * 0.36,
				a - side * base_width_a * 0.36,
				b - side * base_width_b * 0.24,
				b + side * base_width_b * 0.24,
			])
			canvas.draw_colored_polygon(inner, Color(0.93, 0.97, 1.0, foam_alpha))
		var stern: Dictionary = samples[0]
		var stern_pos: Vector2 = _world_to_screen(stern.get("world", Vector2.ZERO))
		var heading: Vector2 = stern.get("heading", Vector2.RIGHT)
		if heading.length_squared() < 0.0001:
			heading = Vector2.RIGHT
		heading = heading.normalized()
		var screen_heading: Vector2 = heading
		var side: Vector2 = Vector2(-screen_heading.y, screen_heading.x).normalized()
		var foam_strength: float = float(stern.get("foam", 0.0))
		var turn_amount: float = float(stern.get("turn_amount", 0.0))
		if foam_strength > 0.01:
			var foam_radius: float = (5.0 + foam_strength * 9.0) * _zoom
			var stern_alpha: float = clampf(0.22 + foam_strength * 0.18, 0.0, 0.34)
			var stern_back: Vector2 = stern_pos - screen_heading * (6.0 + foam_strength * 10.0) * _zoom
			canvas.draw_circle(stern_back, foam_radius, Color(0.92, 0.97, 1.0, stern_alpha))
			if turn_amount > 0.05:
				var side_offset: float = (8.0 + turn_amount * 14.0) * _zoom
				canvas.draw_circle(stern_back + side * side_offset * 0.55, foam_radius * 0.72, Color(0.86, 0.95, 1.0, stern_alpha * 0.9))
				canvas.draw_circle(stern_back - side * side_offset * 0.55, foam_radius * 0.72, Color(0.86, 0.95, 1.0, stern_alpha * 0.9))

func _draw_impacts(canvas: CanvasItem) -> void:
	for event in _water_impacts:
		var impact_world: Vector2 = event.get("world", Vector2.ZERO)
		var t: float = float(event.get("age", 0.0))
		var lifetime: float = maxf(0.001, float(event.get("lifetime", 0.42)))
		var intensity: float = maxf(0.2, float(event.get("intensity", 1.0)))
		var u: float = clampf(t / lifetime, 0.0, 1.0)
		var fade: float = 1.0 - u
		var sp: Vector2 = _world_to_screen(impact_world)
		var impact_scale: float = _zoom * intensity
		for ring in range(3):
			var rr: float = (6.0 + float(ring) * 10.0) * impact_scale * (0.2 + u * 0.95)
			var alpha: float = 0.26 * fade * (1.0 - float(ring) * 0.24)
			canvas.draw_arc(sp, rr, 0.0, TAU, maxi(18, int(22.0 + rr * 0.25)), Color(0.72, 0.88, 0.98, alpha), 1.5 * _zoom, true)
		var foam_radius: float = (4.0 + intensity * 3.0) * impact_scale * (1.0 - u * 0.35)
		canvas.draw_circle(sp, foam_radius, Color(0.94, 0.98, 1.0, 0.12 * fade))

func _world_to_screen(world: Vector2) -> Vector2:
	return _origin + world * _world_scale
