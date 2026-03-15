extends Node3D

@onready var _camera:     Camera3D       = $Camera3D
@onready var _globe_root: Node3D         = $GlobeRoot
@onready var _globe_mesh: MeshInstance3D = $GlobeRoot/Globe
@onready var _atmo_mesh:  MeshInstance3D = $GlobeRoot/Atmosphere

# ── Orbit camera ──────────────────────────────────────────────────────────────
const CAM_DIST_MIN:      float = 1.2
const CAM_DIST_MAX:      float = 10.0
const ZOOM_STEP:         float = 0.1
const ZOOM_SMOOTH:       float = 8.0
const ORBIT_DEG_PER_SEC: float = 90.0   # arrow-key orbit speed
const ELEVATION_LIMIT:   float = 85.0   # keep away from pole singularity

const DEFAULT_CAM_DIST:  float = 3.0
const DEFAULT_AZIMUTH:   float = 0.0
const DEFAULT_ELEVATION: float = 20.0   # slightly above equator

var _cam_dist:       float = DEFAULT_CAM_DIST
var _cam_dist_target: float = DEFAULT_CAM_DIST
var _cam_azimuth:    float = DEFAULT_AZIMUTH    # degrees, horizontal orbit
var _cam_elevation:  float = DEFAULT_ELEVATION  # degrees, vertical orbit

# ── Axial tilt ───────────────────────────────────────────────────────────────
const AXIAL_TILT_DEG: float = 23.5
var   _default_quat:  Quaternion

# ── Time-driven rotation ──────────────────────────────────────────────────────
# 1 real minute = 1 full rotation  →  6 °/s at time_scale 1.0
const BASE_DEG_PER_SEC: float = 0.25   # 360° / 1440 s = 1 rotation per 24 min
const TIME_SCALE_MIN:   float = 0.0
const TIME_SCALE_MAX:   float = 120.0
const SPEED_DRAG_SENS:  float = 0.05
var   _sim_angle:       float = 0.0
var   _time_scale:      float = 1.0


# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_default_quat = Quaternion(Vector3.RIGHT, deg_to_rad(AXIAL_TILT_DEG))
	_apply_globe_texture()
	_apply_atmosphere_material()
	_add_grid_overlay()
	_add_reset_button()
	_update_globe()
	_update_camera()

func _process(delta: float) -> void:
	_sim_angle  += BASE_DEG_PER_SEC * _time_scale * delta
	_cam_dist    = lerpf(_cam_dist, _cam_dist_target, ZOOM_SMOOTH * delta)

	# Arrow-key orbit
	var orbit_speed := ORBIT_DEG_PER_SEC * delta
	if Input.is_key_pressed(KEY_LEFT):
		_cam_azimuth -= orbit_speed
	if Input.is_key_pressed(KEY_RIGHT):
		_cam_azimuth += orbit_speed
	if Input.is_key_pressed(KEY_UP):
		_cam_elevation = clampf(_cam_elevation + orbit_speed, -ELEVATION_LIMIT, ELEVATION_LIMIT)
	if Input.is_key_pressed(KEY_DOWN):
		_cam_elevation = clampf(_cam_elevation - orbit_speed, -ELEVATION_LIMIT, ELEVATION_LIMIT)

	_update_globe()
	_update_camera()

# ── Reset view ────────────────────────────────────────────────────────────────
func _reset_view() -> void:
	_cam_dist_target = DEFAULT_CAM_DIST
	_cam_azimuth     = DEFAULT_AZIMUTH
	_cam_elevation   = DEFAULT_ELEVATION
	_sim_angle       = 0.0
	_time_scale      = 1.0

# ── Input ─────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		match mbe.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_cam_dist_target = clampf(_cam_dist_target - ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_dist_target = clampf(_cam_dist_target + ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)

	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_R:
			_reset_view()

# ── Globe orientation (time-driven, camera-independent) ───────────────────────
func _update_globe() -> void:
	var spin_q := Quaternion(Vector3.UP, deg_to_rad(_sim_angle))
	_globe_root.quaternion = (_default_quat * spin_q).normalized()

# ── Orbit camera ──────────────────────────────────────────────────────────────
func _update_camera() -> void:
	var az := deg_to_rad(_cam_azimuth)
	var el := deg_to_rad(_cam_elevation)
	_camera.position = Vector3(
		sin(az) * cos(el),
		sin(el),
		cos(az) * cos(el)
	) * _cam_dist
	_camera.look_at(Vector3.ZERO, Vector3.UP)

# ── Texture loading ────────────────────────────────────────────────────────────
func _apply_globe_texture() -> void:
	var img := Image.load_from_file("res://assets/maps/globe.png")
	if img == null:
		push_error("globe_arena: cannot load res://assets/maps/globe.png")
		return
	img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.roughness      = 0.85
	mat.metallic       = 0.0
	mat.specular_mode  = BaseMaterial3D.SPECULAR_DISABLED
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

# ── Lat/lon grid overlay ──────────────────────────────────────────────────────
func _add_grid_overlay() -> void:
	var mesh := SphereMesh.new()
	mesh.radius           = 1.003
	mesh.height           = 2.006
	mesh.radial_segments  = 72
	mesh.rings            = 36

	var shader_code := """
shader_type spatial;
render_mode unshaded, cull_back, blend_add;

void fragment() {
\tfloat fx = fract(UV.x * 24.0);
\tfloat fy = fract(UV.y * 12.0);
\tif (fx > 0.012 && fy > 0.012) { discard; }
\tALBEDO = vec3(0.3, 0.7, 1.0) * 0.45;
}
"""

	var shader := Shader.new()
	shader.code = shader_code

	var mat := ShaderMaterial.new()
	mat.shader = shader

	var grid_mesh := MeshInstance3D.new()
	grid_mesh.mesh              = mesh
	grid_mesh.material_override = mat
	_globe_root.add_child(grid_mesh)

# ── Reset button ──────────────────────────────────────────────────────────────
func _add_reset_button() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var btn := Button.new()
	btn.text          = "Reset View  [R]"
	btn.anchor_left   = 1.0
	btn.anchor_right  = 1.0
	btn.anchor_top    = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left   = -160.0
	btn.offset_top    = -52.0
	btn.offset_right  = -12.0
	btn.offset_bottom = -12.0
	canvas.add_child(btn)
	btn.pressed.connect(_reset_view)
