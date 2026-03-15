extends Node3D

@onready var _camera:     Camera3D       = $Camera3D
@onready var _globe_root: Node3D         = $GlobeRoot
@onready var _globe_mesh: MeshInstance3D = $GlobeRoot/Globe
@onready var _atmo_mesh:  MeshInstance3D = $GlobeRoot/Atmosphere

# ── Camera zoom ────────────────────────────────────────────────────────────────
const CAM_DIST_MIN:  float = 1.2
const CAM_DIST_MAX:  float = 6.0
const ZOOM_STEP:     float = 0.25
var _cam_dist: float = 3.0

# ── Rotation ───────────────────────────────────────────────────────────────────
const ROT_SENSITIVITY: float = 0.4   # degrees per pixel
var _dragging:    bool    = false
var _last_mouse:  Vector2 = Vector2.ZERO

# ── Lifecycle ──────────────────────────────────────────────────────────────────
func _ready() -> void:
	_apply_globe_texture()
	_apply_atmosphere_material()
	_update_camera()

# ── Texture loading (mirrors iso_terrain_renderer.gd pattern) ─────────────────
func _apply_globe_texture() -> void:
	var tex := load("res://assets/maps/globe.png") as Texture2D
	if tex == null:
		push_error("globe_arena: cannot load texture resource res://assets/maps/globe.png")
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.85
	mat.metallic  = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_globe_mesh.material_override = mat

# ── Atmosphere halo ────────────────────────────────────────────────────────────
func _apply_atmosphere_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode      = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode       = BaseMaterial3D.CULL_FRONT   # render inner face → limb halo
	mat.albedo_color    = Color(0.35, 0.65, 1.0, 0.10)
	mat.emission_enabled = true
	mat.emission        = Color(0.20, 0.50, 0.95)
	mat.emission_energy_multiplier = 0.15
	_atmo_mesh.material_override = mat

# ── Camera ─────────────────────────────────────────────────────────────────────
func _update_camera() -> void:
	_camera.position = Vector3(0.0, 0.0, _cam_dist)

# ── Input — SolidWorks-style: scroll = zoom, middle-drag = rotate ──────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		match mbe.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_cam_dist = clampf(_cam_dist - ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_dist = clampf(_cam_dist + ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
				_update_camera()
			MOUSE_BUTTON_MIDDLE:
				_dragging   = mbe.pressed
				_last_mouse = mbe.position

	elif event is InputEventMouseMotion and _dragging:
		_rotate_globe((event as InputEventMouseMotion).relative)

# ── Quaternion turntable rotation (no gimbal lock) ─────────────────────────────
func _rotate_globe(delta: Vector2) -> void:
	var yaw_q   := Quaternion(Vector3.UP,    deg_to_rad( delta.x * ROT_SENSITIVITY))
	var pitch_q := Quaternion(Vector3.RIGHT, deg_to_rad( delta.y * ROT_SENSITIVITY))
	# yaw left-multiplied (world space), pitch right-multiplied (local/screen space)
	_globe_root.quaternion = (yaw_q * _globe_root.quaternion * pitch_q).normalized()
