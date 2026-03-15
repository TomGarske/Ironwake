extends Node3D

@onready var _camera:     Camera3D       = $Camera3D
@onready var _globe_root: Node3D         = $GlobeRoot
@onready var _globe_mesh: MeshInstance3D = $GlobeRoot/Globe
@onready var _atmo_mesh:  MeshInstance3D = $GlobeRoot/Atmosphere
@onready var _moon:       Node3D         = $Moon

# ── Focus ─────────────────────────────────────────────────────────────────────
enum Focus { EARTH, MOON, SYSTEM, SOLAR }
var _focus: Focus = Focus.EARTH

const MOON_CAM_DIST_DEFAULT: float = 0.6
const MOON_CAM_DIST_MIN:     float = 0.4
const MOON_CAM_DIST_MAX:     float = 0.6
var _moon_cam_dist:        float = MOON_CAM_DIST_DEFAULT
var _moon_cam_dist_target: float = MOON_CAM_DIST_DEFAULT

const SYSTEM_CAM_DIST_DEFAULT: float = 12.0
const SYSTEM_CAM_DIST_MIN:     float = 6.0
const SYSTEM_CAM_DIST_MAX:     float = 12
# True isometric direction: equal parts right/up/back so orbital plane is clearly visible
const SYSTEM_CAM_DIR: Vector3 = Vector3(1.0, 1.0, 1.0)
var _system_cam_dist:        float = SYSTEM_CAM_DIST_DEFAULT
var _system_cam_dist_target: float = SYSTEM_CAM_DIST_DEFAULT

const SOLAR_CAM_DIST_DEFAULT: float = 40000.0
const SOLAR_CAM_DIST_MIN:     float = 15000.0
const SOLAR_CAM_DIST_MAX:     float = 100000.0
var _solar_cam_dist:        float = SOLAR_CAM_DIST_DEFAULT
var _solar_cam_dist_target: float = SOLAR_CAM_DIST_DEFAULT

# ── Orbit camera ──────────────────────────────────────────────────────────────
const CAM_DIST_MIN:      float = 1.1
const CAM_DIST_MAX:      float = 2.0
const ZOOM_STEP:         float = 0.1
const ZOOM_SMOOTH:       float = 8.0
const ELEVATION_LIMIT:   float = 85.0   # keep away from pole singularity

const DEFAULT_CAM_DIST:  float = 2.0
const DEFAULT_AZIMUTH:   float = 0.0
const DEFAULT_ELEVATION: float = 20.0   # slightly above equator

var _cam_dist:        float = DEFAULT_CAM_DIST
var _cam_dist_target: float = DEFAULT_CAM_DIST

# ── Axial tilt ───────────────────────────────────────────────────────────────
const AXIAL_TILT_DEG: float = 23.5
var   _default_quat:  Quaternion

# ── Time-driven rotation ──────────────────────────────────────────────────────
# At time_scale 1.0: real-time (Earth rotates once per 86400 game-seconds).
# time_scale N = N real seconds per game-second of simulated time.
const BASE_DEG_PER_SEC: float = 360.0 / 86400.0   # ≈ 0.004167°/s
const SPEED_DRAG_SENS:  float = 0.05
const TIME_SCALE_STEPS: Array = [
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
	10, 20, 30, 40, 50, 60, 70, 80, 90,
	100, 200, 300, 400, 500, 600, 700, 800, 900,
	1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000,
	20000, 30000, 40000, 50000, 60000, 70000, 80000, 90000, 100000
]
var   _sim_angle:       float = 0.0
var   _time_scale:      float = 1.0

# ── Solar orbit ────────────────────────────────────────────────────────────────
# True-scale Sun distance (Earth radius = 1.0 → 23480 scene units).
# One orbit = 365.25 days. Starts at PI so Earth begins at scene origin (0,0,0).
const EARTH_ORBIT_DIST:    float = 23480.0
const ORBITAL_DEG_PER_SEC: float = 360.0 / (365.25 * 86400.0)  # ≈ 0.0000114°/s
var   _orbital_angle:      float = PI

# ── Hex selection ─────────────────────────────────────────────────────────────
var _hex_data:        Array          = []   # Array of {c:Vector3, n:Array, p:PackedVector3Array}
var _selected_hex:    int            = 0
var _hex_highlight:   MeshInstance3D = null
var _goldberg_overlay: MeshInstance3D = null
var _hex_grid_visible: bool           = true

# ── Camera tracking ───────────────────────────────────────────────────────────
const CAM_TRACK_SPEED: float = 5.0   # slerp speed toward selected hex
var   _cam_dir: Vector3 = Vector3.ZERO  # smoothed world-space look direction
var   _cam_up:  Vector3 = Vector3.UP    # smoothed up vector — always tracks pole

# ── HUD ───────────────────────────────────────────────────────────────────────
var _focus_label:      Label = null
var _time_scale_label: Label = null


# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_default_quat = Quaternion(Vector3.RIGHT, deg_to_rad(AXIAL_TILT_DEG))
	_load_hex_data()
	_apply_globe_texture()
	_apply_atmosphere_material()
	_add_goldberg_overlay()
	_setup_hex_highlight()
	_add_focus_hud()
	_add_sun()
	_update_globe()
	_update_camera(0.0)

func _process(delta: float) -> void:
	_sim_angle       += BASE_DEG_PER_SEC * _time_scale * delta
	_orbital_angle   += deg_to_rad(ORBITAL_DEG_PER_SEC * _time_scale * delta)
	_cam_dist         = lerpf(_cam_dist, _cam_dist_target, ZOOM_SMOOTH * delta)
	_moon_cam_dist    = lerpf(_moon_cam_dist, _moon_cam_dist_target, ZOOM_SMOOTH * delta)
	_system_cam_dist  = lerpf(_system_cam_dist, _system_cam_dist_target, ZOOM_SMOOTH * delta)
	_solar_cam_dist   = lerpf(_solar_cam_dist, _solar_cam_dist_target, ZOOM_SMOOTH * delta)
	_moon.time_scale  = _time_scale

	var earth_pos            := _calc_earth_pos()
	_globe_root.position      = earth_pos
	_moon.position            = earth_pos

	# SOLAR: bodies are sub-pixel at true scale so mesh sizes are boosted for visibility.
	# SYSTEM: bodies stay at true scale (1.0/0.27); only orbital distance is compressed.
	# This keeps gameplay geometry (hex tiles, collision) untouched in all views.
	if _focus == Focus.SOLAR:
		_globe_root.scale = Vector3.ONE * 80.0
		_moon.scale       = Vector3.ONE
		_moon.set_display_scale(20.0)
	elif _focus == Focus.SYSTEM:
		_globe_root.scale = Vector3.ONE
		_moon.scale       = Vector3.ONE / 12.0   # compresses orbital distance only
		_moon.set_display_scale(12.0)            # cancels node scale so mesh stays true size
	else:
		_globe_root.scale = Vector3.ONE
		_moon.scale       = Vector3.ONE
		_moon.set_display_scale(1.0)

	_update_globe()
	_update_camera(delta)


func _calc_earth_pos() -> Vector3:
	# Earth orbits the Sun at EARTH_ORBIT_DIST. Sun is at (EARTH_ORBIT_DIST, 0, 0).
	return Vector3(
		EARTH_ORBIT_DIST + EARTH_ORBIT_DIST * cos(_orbital_angle),
		0.0,
		EARTH_ORBIT_DIST * sin(_orbital_angle)
	)

# ── Reset view ────────────────────────────────────────────────────────────────
func _reset_view() -> void:
	_sim_angle  = 0.0
	_time_scale = 1.0
	_update_timescale_label()


func _toggle_hex_grid() -> void:
	_hex_grid_visible = not _hex_grid_visible
	if _goldberg_overlay: _goldberg_overlay.visible  = _hex_grid_visible
	if _hex_highlight:    _hex_highlight.visible     = _hex_grid_visible
	_moon.set_hex_grid_visible(_hex_grid_visible)
	# Sync button label — find it by iterating the canvas children
	for canvas in get_children():
		if canvas is CanvasLayer:
			for child in canvas.get_children():
				if child is Button and child.text.begins_with("Grid"):
					child.text = "Grid: ON" if _hex_grid_visible else "Grid: OFF"

# ── Input ─────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		match mbe.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if _focus == Focus.EARTH:
					_cam_dist_target = clampf(_cam_dist_target - ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
				elif _focus == Focus.MOON:
					_moon_cam_dist_target = clampf(_moon_cam_dist_target - ZOOM_STEP * 0.1, MOON_CAM_DIST_MIN, MOON_CAM_DIST_MAX)
				elif _focus == Focus.SYSTEM:
					_system_cam_dist_target = clampf(_system_cam_dist_target - ZOOM_STEP * 2.0, SYSTEM_CAM_DIST_MIN, SYSTEM_CAM_DIST_MAX)
				else:
					_solar_cam_dist_target = clampf(_solar_cam_dist_target - ZOOM_STEP * 20000.0, SOLAR_CAM_DIST_MIN, SOLAR_CAM_DIST_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				if _focus == Focus.EARTH:
					_cam_dist_target = clampf(_cam_dist_target + ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
				elif _focus == Focus.MOON:
					_moon_cam_dist_target = clampf(_moon_cam_dist_target + ZOOM_STEP * 0.1, MOON_CAM_DIST_MIN, MOON_CAM_DIST_MAX)
				elif _focus == Focus.SYSTEM:
					_system_cam_dist_target = clampf(_system_cam_dist_target + ZOOM_STEP * 2.0, SYSTEM_CAM_DIST_MIN, SYSTEM_CAM_DIST_MAX)
				else:
					_solar_cam_dist_target = clampf(_solar_cam_dist_target + ZOOM_STEP * 20000.0, SOLAR_CAM_DIST_MIN, SOLAR_CAM_DIST_MAX)

	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed:
			match key.keycode:
				KEY_LEFT:
					if _focus == Focus.EARTH:
						_navigate_hex(Vector2(-1.0, 0.0))
					else:
						_moon.navigate(Vector2(-1.0, 0.0), _camera.global_transform.basis.x, _camera.global_transform.basis.y)
				KEY_RIGHT:
					if _focus == Focus.EARTH:
						_navigate_hex(Vector2(1.0, 0.0))
					else:
						_moon.navigate(Vector2(1.0, 0.0), _camera.global_transform.basis.x, _camera.global_transform.basis.y)
				KEY_UP:
					if _focus == Focus.EARTH:
						_navigate_hex(Vector2(0.0, 1.0))
					else:
						_moon.navigate(Vector2(0.0, 1.0), _camera.global_transform.basis.x, _camera.global_transform.basis.y)
				KEY_DOWN:
					if _focus == Focus.EARTH:
						_navigate_hex(Vector2(0.0, -1.0))
					else:
						_moon.navigate(Vector2(0.0, -1.0), _camera.global_transform.basis.x, _camera.global_transform.basis.y)
				KEY_EQUAL:  # + / =
					_step_time_scale(1)
				KEY_MINUS:
					_step_time_scale(-1)
				KEY_1:
					if not key.echo:
						_focus = Focus.EARTH
						_cam_dir = Vector3.ZERO
						_time_scale = minf(_time_scale, _max_time_scale())
						_update_focus_label()
						_update_timescale_label()
				KEY_2:
					if not key.echo:
						_focus = Focus.MOON
						_cam_dir = Vector3.ZERO
						_time_scale = minf(_time_scale, _max_time_scale())
						_update_focus_label()
						_update_timescale_label()
				KEY_3:
					if not key.echo:
						_focus = Focus.SYSTEM
						_time_scale = minf(_time_scale, _max_time_scale())
						_update_focus_label()
						_update_timescale_label()
				KEY_4:
					if not key.echo:
						_focus = Focus.SOLAR
						_time_scale = minf(_time_scale, _max_time_scale())
						_update_focus_label()
						_update_timescale_label()
				KEY_R:
					if not key.echo:
						_reset_view()
				KEY_G:
					if not key.echo:
						_toggle_hex_grid()

# ── Globe orientation (time-driven, camera-independent) ───────────────────────
func _update_globe() -> void:
	var spin_q := Quaternion(Vector3.UP, deg_to_rad(_sim_angle))
	_globe_root.quaternion = (_default_quat * spin_q).normalized()

# ── Orbit camera ──────────────────────────────────────────────────────────────
func _update_camera(delta: float) -> void:
	match _focus:
		Focus.MOON:   _update_camera_moon(delta)
		Focus.SYSTEM: _update_camera_system()
		Focus.SOLAR:  _update_camera_solar()
		_:            _update_camera_earth(delta)


func _update_camera_earth(delta: float) -> void:
	var earth_pos := _globe_root.global_position

	if not _hex_data.is_empty():
		var target := (_globe_root.global_transform.basis * (_hex_data[_selected_hex].c as Vector3)).normalized()
		if _cam_dir.is_zero_approx():
			_cam_dir = target
		else:
			_cam_dir = _cam_dir.slerp(target, 1.0 - exp(-CAM_TRACK_SPEED * delta))

	# Always slerp up toward the world north pole so axis is always vertical
	var pole      := (_default_quat * Vector3.UP).normalized()
	var perp      := (pole - _cam_dir * _cam_dir.dot(pole))
	var target_up := perp.normalized() if perp.length_squared() > 1e-4 else Vector3.FORWARD
	_cam_up        = _cam_up.slerp(target_up, 1.0 - exp(-CAM_TRACK_SPEED * delta))

	_camera.position = earth_pos + _cam_dir * _cam_dist
	_camera.look_at(earth_pos, _cam_up)


func _update_camera_moon(delta: float) -> void:
	var moon_center: Vector3 = _moon.get_world_center()
	var hex_world:   Vector3 = _moon.get_selected_hex_world()
	var target:      Vector3 = (hex_world - moon_center).normalized()

	if _cam_dir.is_zero_approx():
		_cam_dir = target
	else:
		_cam_dir = _cam_dir.slerp(target, 1.0 - exp(-CAM_TRACK_SPEED * delta))

	_camera.position = moon_center + _cam_dir * _moon_cam_dist
	_camera.look_at(moon_center, Vector3.UP)


func _update_camera_system() -> void:
	# Fixed isometric overview of the Earth-Moon system.
	# Camera follows Earth so the system stays centred regardless of solar orbit.
	# SYSTEM_CAM_DIR (1,1,1) gives true-isometric elevation (~35°) with the
	# orbital plane (XZ) clearly visible from above-and-to-the-side.
	var earth_pos := _globe_root.global_position
	_camera.position = earth_pos + SYSTEM_CAM_DIR.normalized() * _system_cam_dist
	_camera.look_at(earth_pos, Vector3.UP)


func _update_camera_solar() -> void:
	# Isometric overview of the full solar system — centred on the Sun.
	# Same (1,1,1) direction as the system view so the orbital plane (XZ) reads clearly.
	var sun_pos := Vector3(EARTH_ORBIT_DIST, 0.0, 0.0)
	_camera.position = sun_pos + SYSTEM_CAM_DIR.normalized() * _solar_cam_dist
	_camera.look_at(sun_pos, Vector3.UP)


# ── Texture loading ────────────────────────────────────────────────────────────
func _apply_globe_texture() -> void:
	var tex := load("res://assets/maps/globe.png") as Texture2D
	if tex == null:
		push_error("globe_arena: cannot load res://assets/maps/globe.png")
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_globe_mesh.material_override = mat

# ── Atmosphere halo ────────────────────────────────────────────────────────────
func _apply_atmosphere_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode      = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode       = BaseMaterial3D.CULL_FRONT
	mat.albedo_color    = Color(0.35, 0.65, 1.0, 0.10)
	mat.emission_enabled = true
	mat.emission        = Color(0.20, 0.50, 0.95)
	mat.emission_energy_multiplier = 0.15
	_atmo_mesh.material_override = mat


# ── Goldberg polyhedron overlay ───────────────────────────────────────────────
func _add_goldberg_overlay() -> void:
	var tex := load("res://assets/maps/goldberg_edges.png") as Texture2D
	if tex == null:
		push_error("globe_arena: cannot load res://assets/maps/goldberg_edges.png")
		return

	var shader_code := """
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never;

uniform sampler2D goldberg_tex : hint_default_transparent, filter_linear_mipmap_anisotropic;
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.6;
uniform vec4  edge_color   : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool  show_grid    = true;

void fragment() {
\tif (!show_grid) { discard; }
\tvec4 s = texture(goldberg_tex, UV);
\tALBEDO = edge_color.rgb;
\tALPHA  = s.a * edge_opacity * edge_color.a;
}
"""

	var shader := Shader.new()
	shader.code = shader_code

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("goldberg_tex", tex)
	mat.set_shader_parameter("edge_opacity", 0.6)
	mat.set_shader_parameter("edge_color", Color(1.0, 1.0, 1.0, 1.0))
	mat.set_shader_parameter("show_grid", true)

	var mesh := SphereMesh.new()
	mesh.radius          = 1.004
	mesh.height          = 2.008
	mesh.radial_segments = 128
	mesh.rings           = 64

	var node := MeshInstance3D.new()
	node.name              = "GoldbergOverlay"
	node.mesh              = mesh
	node.material_override = mat
	_globe_root.add_child(node)
	_goldberg_overlay = node

# ── Hex navigation data ────────────────────────────────────────────────────────
func _load_hex_data() -> void:
	var f := FileAccess.open("res://assets/data/goldberg_data.json", FileAccess.READ)
	if f == null:
		push_error("globe_arena: cannot load res://assets/data/goldberg_data.json")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("globe_arena: goldberg_data.json parse failed")
		return
	for face_dict in parsed["faces"]:
		var ca: Array = face_dict["c"]
		var poly_raw: Array = face_dict["p"]
		var poly := PackedVector3Array()
		for pt: Array in poly_raw:
			poly.append(Vector3(pt[0], pt[1], pt[2]))
		_hex_data.append({
			"c": Vector3(ca[0], ca[1], ca[2]),
			"n": face_dict["n"],
			"p": poly,
		})
	# Start on the hex nearest the equator at prime meridian
	var best := 0
	var best_d := INF
	for i in range(_hex_data.size()):
		var d := (_hex_data[i].c as Vector3).distance_to(Vector3(-1.0, 0.0, 0.0))
		if d < best_d:
			best_d = d
			best = i
	_selected_hex = best

func _setup_hex_highlight() -> void:
	var shader_code := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

void fragment() {
\tfloat pulse = 0.55 + 0.45 * sin(TIME * 4.0);
\tALBEDO = vec3(0.2, 0.75, 1.0) * (1.5 * pulse);
\tALPHA  = 0.9 * pulse;
}
"""
	var shader := Shader.new()
	shader.code = shader_code
	var mat := ShaderMaterial.new()
	mat.shader = shader

	_hex_highlight = MeshInstance3D.new()
	_hex_highlight.name = "HexHighlight"
	_hex_highlight.material_override = mat
	_globe_root.add_child(_hex_highlight)
	_update_hex_highlight()

func _update_hex_highlight() -> void:
	if _hex_data.is_empty() or _hex_highlight == null:
		return
	var poly: PackedVector3Array = _hex_data[_selected_hex].p
	var n := poly.size()
	var sum := Vector3.ZERO
	for v in poly:
		sum += v
	var center := (sum / n).normalized() * 1.012

	var verts := PackedVector3Array()
	for i in range(n):
		verts.append(center)
		verts.append(poly[i] * 1.012)
		verts.append(poly[(i + 1) % n] * 1.012)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_hex_highlight.mesh = arr_mesh

func _navigate_hex(dir: Vector2) -> void:
	if _hex_data.is_empty():
		return
	var neighbors: Array = _hex_data[_selected_hex].n
	if neighbors.is_empty():
		return
	var glob_basis  := _globe_root.global_transform.basis
	var cam_right   := _camera.global_transform.basis.x
	var cam_up      := _camera.global_transform.basis.y
	var cur_world   := glob_basis * (_hex_data[_selected_hex].c as Vector3)
	var best: int   = int(neighbors[0])
	var best_score  := -INF
	for ni in neighbors:
		var nw    := glob_basis * (_hex_data[int(ni)].c as Vector3)
		var delta := nw - cur_world
		var score := delta.dot(cam_right) * dir.x + delta.dot(cam_up) * dir.y
		if score > best_score:
			best_score = score
			best = int(ni)
	_selected_hex = best
	_update_hex_highlight()


# ── HUD setup ─────────────────────────────────────────────────────────────────
func _add_focus_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# Focus label — bottom-left
	_focus_label = Label.new()
	_focus_label.anchor_left   = 0.0
	_focus_label.anchor_right  = 0.0
	_focus_label.anchor_top    = 1.0
	_focus_label.anchor_bottom = 1.0
	_focus_label.offset_left   = 12.0
	_focus_label.offset_top    = -44.0
	_focus_label.offset_right  = 300.0
	_focus_label.offset_bottom = -12.0
	_focus_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.8))
	canvas.add_child(_focus_label)
	_update_focus_label()

	# Timescale row — bottom-right: [−]  label  [+]
	var hbox := HBoxContainer.new()
	hbox.anchor_left   = 1.0
	hbox.anchor_right  = 1.0
	hbox.anchor_top    = 1.0
	hbox.anchor_bottom = 1.0
	hbox.offset_left   = -200.0
	hbox.offset_top    = -44.0
	hbox.offset_right  = -12.0
	hbox.offset_bottom = -12.0
	hbox.alignment     = BoxContainer.ALIGNMENT_END
	canvas.add_child(hbox)

	var btn_slow := Button.new()
	btn_slow.text = "−"
	btn_slow.pressed.connect(func(): _step_time_scale(-1))
	hbox.add_child(btn_slow)

	_time_scale_label = Label.new()
	_time_scale_label.custom_minimum_size = Vector2(110, 0)
	_time_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_scale_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.8))
	hbox.add_child(_time_scale_label)

	var btn_fast := Button.new()
	btn_fast.text = "+"
	btn_fast.pressed.connect(func(): _step_time_scale(1))
	hbox.add_child(btn_fast)

	_update_timescale_label()

	# Grid toggle button — top-right
	var grid_btn := Button.new()
	grid_btn.text = "Grid: ON"
	grid_btn.anchor_left   = 1.0
	grid_btn.anchor_right  = 1.0
	grid_btn.anchor_top    = 0.0
	grid_btn.anchor_bottom = 0.0
	grid_btn.offset_left   = -110.0
	grid_btn.offset_top    = 12.0
	grid_btn.offset_right  = -12.0
	grid_btn.offset_bottom = 44.0
	grid_btn.pressed.connect(func(): _toggle_hex_grid())
	canvas.add_child(grid_btn)


func _update_focus_label() -> void:
	if _focus_label == null:
		return
	match _focus:
		Focus.EARTH:  _focus_label.text = "[1] Earth  |  2: Moon  |  3: System  |  4: Solar"
		Focus.MOON:   _focus_label.text = "1: Earth  |  [2] Moon  |  3: System  |  4: Solar"
		Focus.SYSTEM: _focus_label.text = "1: Earth  |  2: Moon  |  [3] System  |  4: Solar"
		Focus.SOLAR:  _focus_label.text = "1: Earth  |  2: Moon  |  3: System  |  [4] Solar"


func _add_sun() -> void:
	const SUN_RADIUS: float = 109.3

	var mat := StandardMaterial3D.new()
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color               = Color(1.0, 0.98, 0.85, 1.0)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.92, 0.60)
	mat.emission_energy_multiplier = 3.0

	var mesh := SphereMesh.new()
	mesh.radius          = SUN_RADIUS
	mesh.height          = SUN_RADIUS * 2.0
	mesh.radial_segments = 32
	mesh.rings           = 16

	var node               := MeshInstance3D.new()
	node.name              = "Sun"
	node.mesh              = mesh
	node.material_override = mat
	node.position          = Vector3(EARTH_ORBIT_DIST, 0.0, 0.0)
	add_child(node)


func _max_time_scale() -> float:
	match _focus:
		Focus.EARTH:  return 1000.0
		Focus.MOON:   return 10000.0
		Focus.SYSTEM: return 100000.0
		Focus.SOLAR:  return 1000000.0
	return 1000.0


func _step_time_scale(direction: int) -> void:
	var max_ts := _max_time_scale()
	var steps: Array = TIME_SCALE_STEPS
	if direction > 0:
		for v in steps:
			if v > _time_scale + 0.001 and v <= max_ts:
				_time_scale = v
				_update_timescale_label()
				return
	else:
		for i in range(steps.size() - 1, -1, -1):
			if steps[i] < _time_scale - 0.001:
				_time_scale = steps[i]
				_update_timescale_label()
				return


func _update_timescale_label() -> void:
	if _time_scale_label == null:
		return
	if _time_scale == 0.0:
		_time_scale_label.text = "PAUSED"
	else:
		_time_scale_label.text = "x%d" % int(_time_scale)
