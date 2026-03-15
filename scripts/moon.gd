extends Node3D

# ── Exports ───────────────────────────────────────────────────────────────────
@export var time_scale:            float = 1.0
@export var orbit_speed:           float = 1.0
@export var rotation_speed:        float = 1.0   # kept == orbit_speed for tidal lock
@export var moon_radius:           float = 0.27
@export var surface_roughness:     float = 0.9
@export var displacement_strength: float = 0.04

@export_group("Surface Colors")
@export var crater_shadow: Color = Color("#0F0F0F")
@export var mare_basalt:   Color = Color("#1A1A1A")
@export var regolith:      Color = Color("#2B2B2B")
@export var highland:      Color = Color("#3D3D3D")
@export var ejecta_ray:    Color = Color("#4A4A4A")

# ── Constants ─────────────────────────────────────────────────────────────────
const ORBIT_DIST:           float = 60.0
# 27.3 day orbit at time_scale=1 is imperceptibly slow; useful range needs time_scale >> 1
const BASE_ORBIT_DEG_PER_SEC: float = 360.0 / (27.3 * 86400.0)

# ── Internal nodes ────────────────────────────────────────────────────────────
var _moon_mesh:      MeshInstance3D = null
var _moon_mat:       ShaderMaterial  = null
var _hex_overlay:    MeshInstance3D = null
var _hex_highlight:  MeshInstance3D = null

# ── Hex navigation ────────────────────────────────────────────────────────────
var _hex_data:    Array = []
var _selected_hex: int  = 0

# ── Orbital state ─────────────────────────────────────────────────────────────
var _orbit_angle: float = 0.0


# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_moon_mesh()
	_build_hex_overlay()
	_load_hex_data()
	_setup_hex_highlight()

func _process(delta: float) -> void:
	_orbit_angle += BASE_ORBIT_DEG_PER_SEC * orbit_speed * time_scale * delta
	rotation_degrees.y = _orbit_angle   # pivot rotates → Moon orbits; tidal lock is automatic

	# Update Earthshine direction each frame
	if _moon_mat != null and _moon_mesh != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var to_earth := (Vector3.ZERO - _moon_mesh.global_position).normalized()
			var view_dir := cam.global_transform.basis.inverse() * to_earth
			_moon_mat.set_shader_parameter("earth_dir_view", view_dir)


# ── Moon mesh ─────────────────────────────────────────────────────────────────
func _build_moon_mesh() -> void:
	var mesh      := SphereMesh.new()
	mesh.radius          = moon_radius
	mesh.height          = moon_radius * 2.0
	mesh.radial_segments = 128
	mesh.rings           = 64

	_moon_mat = _build_surface_material()

	_moon_mesh               = MeshInstance3D.new()
	_moon_mesh.name          = "MoonMesh"
	_moon_mesh.mesh          = mesh
	_moon_mesh.material_override = _moon_mat
	_moon_mesh.position      = Vector3(ORBIT_DIST, 0.0, 0.0)
	# 180° Y so near-side texture center (+X UV) faces toward Earth (-X local of pivot)
	_moon_mesh.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	add_child(_moon_mesh)


func _build_surface_material() -> ShaderMaterial:
	var shader_code := """
shader_type spatial;

uniform sampler2D albedo_tex    : hint_default_white,  filter_linear_mipmap_anisotropic;
uniform sampler2D displacement_tex : hint_default_black, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex    : hint_normal,         filter_linear_mipmap_anisotropic;

uniform float displacement_strength : hint_range(0.0, 0.2) = 0.04;
uniform float surface_roughness     : hint_range(0.0, 1.0) = 0.9;

uniform vec4 crater_shadow : source_color = vec4(0.059, 0.059, 0.059, 1.0);
uniform vec4 mare_basalt   : source_color = vec4(0.102, 0.102, 0.102, 1.0);
uniform vec4 regolith      : source_color = vec4(0.169, 0.169, 0.169, 1.0);
uniform vec4 highland      : source_color = vec4(0.239, 0.239, 0.239, 1.0);
uniform vec4 ejecta_ray    : source_color = vec4(0.290, 0.290, 0.290, 1.0);

uniform vec3 earth_dir_view = vec3(0.0, 0.0, -1.0);

void vertex() {
	float disp = texture(displacement_tex, UV).r;
	VERTEX += NORMAL * disp * displacement_strength;
}

void fragment() {
	float lum = dot(texture(albedo_tex, UV).rgb, vec3(0.2126, 0.7152, 0.0722));

	vec3 col = mix(crater_shadow.rgb,
	               mix(mare_basalt.rgb,
	                   mix(regolith.rgb,
	                       mix(highland.rgb, ejecta_ray.rgb,
	                           smoothstep(0.75, 1.0, lum)),
	                       smoothstep(0.5, 0.75, lum)),
	                   smoothstep(0.25, 0.5, lum)),
	               smoothstep(0.0, 0.25, lum));

	ALBEDO     = col;
	ROUGHNESS  = surface_roughness;
	METALLIC   = 0.0;
	NORMAL_MAP = texture(normal_tex, UV).rgb;

	// Earthshine: faint blue glow on the Earth-facing hemisphere
	float earthshine = max(0.0, dot(NORMAL, normalize(earth_dir_view)));
	EMISSION = vec3(0.05, 0.12, 0.22) * earthshine * 0.08;
}
"""
	var shader := Shader.new()
	shader.code = shader_code

	var mat := ShaderMaterial.new()
	mat.shader = shader

	# Load NASA CGI Moon Kit textures — graceful fallback if missing
	mat.set_shader_parameter("albedo_tex",       _load_tex("res://assets/maps/moon_albedo.png"))
	mat.set_shader_parameter("displacement_tex", _load_tex("res://assets/maps/moon_displacement.png"))
	mat.set_shader_parameter("normal_tex",       _load_tex("res://assets/maps/moon_normal.png"))
	mat.set_shader_parameter("displacement_strength", displacement_strength)
	mat.set_shader_parameter("surface_roughness",     surface_roughness)
	mat.set_shader_parameter("crater_shadow", crater_shadow)
	mat.set_shader_parameter("mare_basalt",   mare_basalt)
	mat.set_shader_parameter("regolith",      regolith)
	mat.set_shader_parameter("highland",      highland)
	mat.set_shader_parameter("ejecta_ray",    ejecta_ray)

	return mat


func _load_tex(path: String) -> Texture2D:
	var t := load(path) as Texture2D
	if t == null:
		push_warning("moon: texture not found: " + path + " (place NASA CGI Moon Kit files)")
	return t


# ── Goldberg hex overlay ──────────────────────────────────────────────────────
func _build_hex_overlay() -> void:
	var tex := load("res://assets/maps/moon_goldberg_edges.png") as Texture2D
	if tex == null:
		push_warning("moon: cannot load moon_goldberg_edges.png")
		return

	var shader_code := """
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never;

uniform sampler2D goldberg_tex : hint_default_transparent, filter_linear_mipmap_anisotropic;
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.5;
uniform vec4  edge_color   : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 s = texture(goldberg_tex, UV);
	ALBEDO = edge_color.rgb;
	ALPHA  = s.a * edge_opacity * edge_color.a;
}
"""
	var shader := Shader.new()
	shader.code = shader_code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("goldberg_tex",  tex)
	mat.set_shader_parameter("edge_opacity",  0.5)
	mat.set_shader_parameter("edge_color",    Color(1.0, 1.0, 1.0, 1.0))

	var overlay_mesh        := SphereMesh.new()
	overlay_mesh.radius          = moon_radius * 1.004
	overlay_mesh.height          = moon_radius * 1.004 * 2.0
	overlay_mesh.radial_segments = 128
	overlay_mesh.rings           = 64

	_hex_overlay               = MeshInstance3D.new()
	_hex_overlay.name          = "HexOverlay"
	_hex_overlay.mesh          = overlay_mesh
	_hex_overlay.material_override = mat
	_moon_mesh.add_child(_hex_overlay)


# ── Hex data loading ──────────────────────────────────────────────────────────
func _load_hex_data() -> void:
	var f := FileAccess.open("res://assets/data/moon_goldberg_data.json", FileAccess.READ)
	if f == null:
		push_error("moon: cannot load moon_goldberg_data.json")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("moon: moon_goldberg_data.json parse failed")
		return
	for face_dict in parsed["faces"]:
		var ca: Array    = face_dict["c"]
		var poly_raw: Array = face_dict["p"]
		var poly := PackedVector3Array()
		for pt: Array in poly_raw:
			poly.append(Vector3(pt[0], pt[1], pt[2]))
		_hex_data.append({
			"c": Vector3(ca[0], ca[1], ca[2]),
			"n": face_dict["n"],
			"p": poly,
		})
	# Start on hex nearest the equator at prime meridian
	var best   := 0
	var best_d := INF
	for i in range(_hex_data.size()):
		var d := (_hex_data[i].c as Vector3).distance_to(Vector3(1.0, 0.0, 0.0))
		if d < best_d:
			best_d = d
			best   = i
	_selected_hex = best


# ── Hex highlight ─────────────────────────────────────────────────────────────
func _setup_hex_highlight() -> void:
	if _moon_mesh == null:
		return
	var shader_code := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

void fragment() {
	float pulse = 0.55 + 0.45 * sin(TIME * 4.0);
	ALBEDO = vec3(0.9, 0.8, 0.3) * (1.5 * pulse);
	ALPHA  = 0.9 * pulse;
}
"""
	var shader := Shader.new()
	shader.code = shader_code
	var mat := ShaderMaterial.new()
	mat.shader = shader

	_hex_highlight               = MeshInstance3D.new()
	_hex_highlight.name          = "HexHighlight"
	_hex_highlight.material_override = mat
	_moon_mesh.add_child(_hex_highlight)
	_update_hex_highlight()


func _update_hex_highlight() -> void:
	if _hex_data.is_empty() or _hex_highlight == null:
		return
	var poly: PackedVector3Array = _hex_data[_selected_hex].p
	var n    := poly.size()
	var sum  := Vector3.ZERO
	for v in poly:
		sum += v
	var center := (sum / n).normalized() * (moon_radius * 1.012)

	var verts := PackedVector3Array()
	for i in range(n):
		verts.append(center)
		verts.append(poly[i] * (moon_radius * 1.012))
		verts.append(poly[(i + 1) % n] * (moon_radius * 1.012))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_hex_highlight.mesh = arr_mesh


# ── Public API (called by globe_arena.gd) ─────────────────────────────────────
func get_world_center() -> Vector3:
	if _moon_mesh == null:
		return Vector3.ZERO
	return _moon_mesh.global_position


func get_selected_hex_world() -> Vector3:
	if _hex_data.is_empty() or _moon_mesh == null:
		return _moon_mesh.global_position if _moon_mesh else Vector3.ZERO
	var local_c: Vector3 = _hex_data[_selected_hex].c
	return _moon_mesh.global_transform * (local_c * moon_radius)


func navigate(dir: Vector2, cam_right: Vector3, cam_up: Vector3) -> void:
	if _hex_data.is_empty():
		return
	var neighbors: Array = _hex_data[_selected_hex].n
	if neighbors.is_empty():
		return
	var basis    := _moon_mesh.global_transform.basis
	var cur_world := basis * (_hex_data[_selected_hex].c as Vector3)
	var best: int  = int(neighbors[0])
	var best_score := -INF
	for ni in neighbors:
		var nw    := basis * (_hex_data[int(ni)].c as Vector3)
		var delta := nw - cur_world
		var score := delta.dot(cam_right) * dir.x + delta.dot(cam_up) * dir.y
		if score > best_score:
			best_score = score
			best       = int(ni)
	_selected_hex = best
	_update_hex_highlight()
