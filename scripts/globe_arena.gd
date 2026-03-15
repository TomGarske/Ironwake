extends Node3D

@onready var _camera:     Camera3D       = $Camera3D
@onready var _globe_root: Node3D         = $GlobeRoot
@onready var _globe_mesh: MeshInstance3D = $GlobeRoot/Globe
@onready var _atmo_mesh:  MeshInstance3D = $GlobeRoot/Atmosphere

# ── Camera zoom ─────────────────────────────────────────────────────────────
const CAM_DIST_MIN:     float = 1.2
const CAM_DIST_MAX:     float = 6.0
const ZOOM_STEP:        float = 0.25
const ZOOM_SMOOTH:      float = 8.0
const DEFAULT_CAM_DIST: float = 3.0
var _cam_dist:          float = DEFAULT_CAM_DIST
var _cam_dist_target:   float = DEFAULT_CAM_DIST

# ── Camera pan ───────────────────────────────────────────────────────────────
const PAN_LIMIT:   float = 2.0
const PAN_SMOOTH:  float = 8.0
var _cam_offset:        Vector2 = Vector2.ZERO
var _cam_offset_target: Vector2 = Vector2.ZERO

# ── Axial tilt & auto-rotation ────────────────────────────────────────────────
const AXIAL_TILT_DEG:   float = 23.5
const AUTO_ROT_DEG_SEC: float = 5.0   # slow realistic spin
var   _axial_tilt_axis: Vector3        # computed in _ready

# ── Globe quaternion state ────────────────────────────────────────────────────
const ROT_SENSITIVITY: float = 0.4    # degrees per pixel drag
var   _globe_quat:     Quaternion = Quaternion.IDENTITY
var   _default_quat:   Quaternion      # starting orientation, used by Reset

# ── Drag state ───────────────────────────────────────────────────────────────
var _left_dragging:  bool    = false
var _pan_dragging:   bool    = false   # middle OR right button
var _last_mouse:     Vector2 = Vector2.ZERO

# ── Spin momentum ─────────────────────────────────────────────────────────────
const SPIN_DAMPING:   float = 0.88    # per-frame velocity decay (< 1)
const SPIN_MIN_SQ:    float = 0.0001  # stop threshold (squared)
var   _spin_velocity: Vector2 = Vector2.ZERO

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	# _default_quat rotates around +X by 23.5°, so the north pole ends up at
	# (0, cos23.5°, sin23.5°).  The auto-rotation axis must match that direction.
	_axial_tilt_axis = Vector3(
		0.0,
		cos(deg_to_rad(AXIAL_TILT_DEG)),
		sin(deg_to_rad(AXIAL_TILT_DEG))
	).normalized()
	# Start with tilt visible so the poles are off-vertical
	_default_quat = Quaternion(Vector3.RIGHT, deg_to_rad(AXIAL_TILT_DEG))
	_globe_quat   = _default_quat

	_apply_globe_texture()
	_apply_atmosphere_material()
	_add_reset_button()
	_apply_globe_quat()
	_update_camera()

func _process(delta: float) -> void:
	var grabbing := _left_dragging or _pan_dragging

	# Auto-rotation around tilted axis — paused while user holds the globe
	if not grabbing:
		var auto_q := Quaternion(_axial_tilt_axis, deg_to_rad(AUTO_ROT_DEG_SEC * delta))
		_globe_quat = (auto_q * _globe_quat).normalized()

	# Spin momentum — only while not actively dragging
	if not _left_dragging and _spin_velocity.length_squared() > SPIN_MIN_SQ:
		_rotate_globe(_spin_velocity * delta * 60.0)   # normalise to ~60 fps feel
		_spin_velocity *= SPIN_DAMPING
		if _spin_velocity.length_squared() < SPIN_MIN_SQ:
			_spin_velocity = Vector2.ZERO

	# Smooth zoom & pan
	_cam_dist   = lerpf(_cam_dist, _cam_dist_target, ZOOM_SMOOTH * delta)
	_cam_offset = _cam_offset.lerp(_cam_offset_target, PAN_SMOOTH * delta)

	_apply_globe_quat()
	_update_camera()

# ── Reset view ────────────────────────────────────────────────────────────────
func _reset_view() -> void:
	_cam_dist_target   = DEFAULT_CAM_DIST
	_cam_offset_target = Vector2.ZERO
	_spin_velocity     = Vector2.ZERO
	_globe_quat        = _default_quat

# ── Input ─────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		match mbe.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_cam_dist_target = clampf(_cam_dist_target - ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_dist_target = clampf(_cam_dist_target + ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
			MOUSE_BUTTON_LEFT:
				_left_dragging = mbe.pressed
				if mbe.pressed:
					_last_mouse    = mbe.position
					_spin_velocity = Vector2.ZERO   # kill momentum on grab
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_pan_dragging = mbe.pressed
				if mbe.pressed:
					_last_mouse = mbe.position

	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _left_dragging:
			# Track raw delta for momentum; convert to per-frame velocity
			_spin_velocity = motion.relative
			_rotate_globe(motion.relative)
		elif _pan_dragging:
			var pan_scale := 0.0015 * _cam_dist   # pan slower when zoomed in
			_cam_offset_target.y += motion.relative.y * pan_scale
			_cam_offset_target.y = clampf(_cam_offset_target.y, -PAN_LIMIT, PAN_LIMIT)

	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_R:
			_reset_view()

# ── Rotate only around the tilted spin axis (no pitch / axis-tipping) ────────
func _rotate_globe(delta: Vector2) -> void:
	var spin_q := Quaternion(_axial_tilt_axis, deg_to_rad(delta.x * ROT_SENSITIVITY))
	_globe_quat = (spin_q * _globe_quat).normalized()

func _apply_globe_quat() -> void:
	_globe_root.quaternion = _globe_quat

# ── Camera ─────────────────────────────────────────────────────────────────────
func _update_camera() -> void:
	_camera.position = Vector3(_cam_offset.x, _cam_offset.y, _cam_dist)
	_camera.look_at(Vector3.ZERO, Vector3.UP)

# ── Texture loading ────────────────────────────────────────────────────────────
func _apply_globe_texture() -> void:
	var img := Image.load_from_file("res://assets/maps/globe.png")
	if img == null:
		push_error("globe_arena: cannot load res://assets/maps/globe.png")
		return
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
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

# ── Reset button (bottom-right HUD overlay) ───────────────────────────────────
func _add_reset_button() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var btn := Button.new()
	btn.text        = "Reset View  [R]"
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
