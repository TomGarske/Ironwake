## conquest_arena.gd
## Conquest game mode — classic Risk-style territory control on a 3D globe.
##
## Uses the Goldberg polyhedron hex grid from the project's globe system.
## Each of the 42 classic Risk territories owns a cluster of goldberg hexes,
## colored by the controlling player.
##
## Architecture:
##   - Game logic lives in conquest/ subsystems (pure GDScript, no Nodes).
##   - Globe rendering: 3D sphere + goldberg hex overlay + territory color mesh.
##   - UI via CanvasLayer overlay.
##   - State machine: ConquestPhase enum drives all phase transitions.
##
## Integration points reused from Ironwake:
##   - GameManager: player registry, mode selection, offline test setup.
##   - DebugOverlay: log_message() for all debug output.
##   - Globe assets: goldberg_data.json, globe.png, goldberg_edges.png.

extends Node3D

# ---------------------------------------------------------------------------
# Conquest subsystem preloads
# ---------------------------------------------------------------------------
const ConquestData   := preload("res://scripts/game_modes/conquest/conquest_data.gd")
const ConquestBoard  := preload("res://scripts/game_modes/conquest/conquest_board_builder.gd")
const ConquestTM     := preload("res://scripts/game_modes/conquest/conquest_territory_manager.gd")
const ConquestSpawn  := preload("res://scripts/game_modes/conquest/conquest_spawn_resolver.gd")
const ConquestCombat := preload("res://scripts/game_modes/conquest/conquest_combat_resolver.gd")
const ConquestPath   := preload("res://scripts/game_modes/conquest/conquest_path_service.gd")
const ConquestAI     := preload("res://scripts/game_modes/conquest/conquest_ai.gd")
const ConquestDebug  := preload("res://scripts/game_modes/conquest/conquest_debug_tools.gd")

# ---------------------------------------------------------------------------
# Globe constants
# ---------------------------------------------------------------------------
const CAM_DIST_MIN: float   = 1.3
const CAM_DIST_MAX: float   = 6.0
const CAM_DIST_DEFAULT: float = 2.0
const ZOOM_STEP: float      = 0.12
const ZOOM_SMOOTH: float    = 8.0
const CAM_TRACK_SPEED: float = 5.0
const AXIAL_TILT_DEG: float = 0.0  # No tilt for strategy map clarity.
const TERRITORY_LABEL_SCALE: float = 0.008

# ---------------------------------------------------------------------------
# Visual constants
# ---------------------------------------------------------------------------
const UNOWNED_COLOR: Color       = Color(0.25, 0.25, 0.28, 0.35)
## Classic Risk continent colors — used as base territory tint.
const CONTINENT_COLORS: Dictionary = {
	"north_america": Color(0.92, 0.85, 0.25, 0.80),  # Yellow
	"south_america": Color(0.85, 0.20, 0.15, 0.80),  # Red
	"europe":        Color(0.20, 0.55, 0.85, 0.80),   # Blue
	"africa":        Color(0.85, 0.55, 0.15, 0.80),   # Orange/Brown
	"asia":          Color(0.18, 0.65, 0.30, 0.80),    # Green
	"australia":     Color(0.70, 0.22, 0.70, 0.80),    # Purple
}
const HIGHLIGHT_COLOR: Color     = Color(1.0, 0.95, 0.3, 0.75)
const SELECTION_COLOR: Color     = Color(1.0, 1.0, 1.0, 0.85)
const VALID_TARGET_COLOR: Color  = Color(0.3, 1.0, 0.5, 0.6)
const HUD_BG: Color              = Color(0.08, 0.06, 0.05, 0.90)
const HUD_BORDER: Color          = Color(0.48, 0.35, 0.22, 0.84)
const HUD_TEXT: Color            = Color(0.95, 0.90, 0.83, 1.0)
const HUD_TEXT_DIM: Color        = Color(0.70, 0.63, 0.55, 1.0)
const HUD_ACCENT: Color          = Color(0.95, 0.88, 0.40, 1.0)
const PHASE_COLORS: Dictionary   = {
	ConquestData.ConquestPhase.ROLL_FOR_ORDER:  Color(0.90, 0.80, 0.30),
	ConquestData.ConquestPhase.TERRITORY_DRAFT: Color(0.60, 0.82, 1.0),
	ConquestData.ConquestPhase.ARMY_PLACEMENT:  Color(0.50, 0.90, 0.60),
	ConquestData.ConquestPhase.REINFORCE:       Color(0.38, 0.82, 0.42),
	ConquestData.ConquestPhase.ATTACK:          Color(0.95, 0.35, 0.28),
	ConquestData.ConquestPhase.FORTIFY:         Color(0.60, 0.48, 1.0),
}
const PHASE_NAMES: Dictionary = {
	ConquestData.ConquestPhase.MATCH_SETUP:     "SETUP",
	ConquestData.ConquestPhase.ROLL_FOR_ORDER:  "ROLL FOR ORDER",
	ConquestData.ConquestPhase.TERRITORY_DRAFT: "TERRITORY DRAFT",
	ConquestData.ConquestPhase.ARMY_PLACEMENT:  "ARMY PLACEMENT",
	ConquestData.ConquestPhase.TURN_START:      "TURN START",
	ConquestData.ConquestPhase.REINFORCE:       "REINFORCE",
	ConquestData.ConquestPhase.ATTACK:          "ATTACK",
	ConquestData.ConquestPhase.FORTIFY:         "FORTIFY",
	ConquestData.ConquestPhase.TURN_END:        "END TURN",
	ConquestData.ConquestPhase.GAME_OVER:       "GAME OVER",
}

# ---------------------------------------------------------------------------
# Scene node references
# ---------------------------------------------------------------------------
@onready var _camera: Camera3D = $Camera3D
@onready var _globe_root: Node3D = $GlobeRoot
@onready var _globe_mesh: MeshInstance3D = $GlobeRoot/Globe
@onready var _atmo_mesh: MeshInstance3D = $GlobeRoot/Atmosphere

# ---------------------------------------------------------------------------
# Globe state
# ---------------------------------------------------------------------------
var _cam_dist: float = CAM_DIST_DEFAULT
var _cam_dist_target: float = CAM_DIST_DEFAULT
## Camera starts looking at Africa. Godot convention: -X = prime meridian, +Y = north.
var _cam_dir: Vector3 = Vector3(0.95, 0.15, 0.27).normalized()
var _cam_up: Vector3 = Vector3.UP  # Y=up in Godot convention
var _default_quat: Quaternion
## Timer for auto-advancing setup phases (roll display, AI draft turns).
var _setup_timer: float = 0.0
## When true, camera slerps toward _cam_track_target. Set on territory selection, clears after arriving.
var _cam_tracking: bool = false
var _cam_track_target: Vector3 = Vector3.ZERO

## Goldberg hex data: Array of { c: Vector3, n: Array[int], p: PackedVector3Array }
var _hex_data: Array = []
## Hex → territory_id mapping. Index matches _hex_data index.
var _hex_territory_map: Array[String] = []
## MeshInstance3D for the territory color overlay.
var _territory_overlay: MeshInstance3D = null
## MeshInstance3D for the selected territory highlight.
var _selection_overlay: MeshInstance3D = null
## MeshInstance3D for territory border lines.
var _border_overlay: MeshInstance3D = null
## Label3D nodes: territory_id → Label3D for army count.
var _army_labels: Dictionary = {}
## Label3D nodes: territory_id → Label3D for territory name.
var _name_labels: Dictionary = {}
## Label3D nodes: region_id → Label3D for continent name.
var _region_labels: Dictionary = {}
## Hex terrain types parallel to _hex_territory_map.
var _hex_terrain_types: Array[int] = []
## Land mask: 1 = land, 0 = ocean. Loaded from hex_land_mask.json.
var _hex_land_mask: Array[int] = []

# ---------------------------------------------------------------------------
# Conquest state
# ---------------------------------------------------------------------------
var _cqs: ConquestData.ConquestGameState = null
var _combat_obj = null  # ConquestCombat instance

## Interaction state.
var _selected_territory_id: String = ""
var _hover_territory_id: String = ""
var _fortify_source_id: String = ""
var _pending_attack_from: String = ""

## Recent combat log lines.
var _combat_log: Array[String] = []
const COMBAT_LOG_MAX: int = 12

## Dice display state.
var _dice_display_timer: float = 0.0
var _dice_display_data: Dictionary = {}
const DICE_DISPLAY_DURATION: float = 2.5

## Local player.
var _local_player_id: int = 0
var _ai_player_count: int = 3
var _conquest_initialized: bool = false
var _territory_mesh_dirty: bool = true

# ---------------------------------------------------------------------------
# UI nodes (created in _ready)
# ---------------------------------------------------------------------------
var _ui_layer: CanvasLayer = null
var _hud_draw: Control = null
var _end_phase_button: Button = null
var _end_turn_button: Button = null
var _combat_log_label: Label = null
var _quit_button: Button = null
var _continue_button: Button = null
var _next_unclaimed_button: Button = null
## Index into unclaimed territory list for cycling.
var _unclaimed_cycle_index: int = 0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_default_quat = Quaternion(Vector3.RIGHT, deg_to_rad(AXIAL_TILT_DEG))
	_load_hex_data()
	_apply_globe_texture()
	_apply_atmosphere_material()
	_add_goldberg_overlay()
	_setup_territory_overlay()
	_setup_selection_overlay()
	_setup_border_overlay()
	_setup_ui()
	_update_globe()

	if GameManager != null:
		_ai_player_count = clampi(GameManager.sp_conquest_factions, 1, 5)

	_combat_obj = ConquestCombat.new()
	_init_conquest()
	_update_camera(0.0)

	DebugOverlay.log_message("[ConquestArena] Globe conquest ready. %d hexes loaded." % _hex_data.size())

	# DEBUG: Log scene tree structure and transforms.
	DebugOverlay.log_message("[DEBUG] globe_root children: %d" % _globe_root.get_child_count())
	for child in _globe_root.get_children():
		DebugOverlay.log_message("[DEBUG]   child: %s type=%s visible=%s pos=%s scale=%s" % [
			child.name, child.get_class(), str(child.visible), str(child.position), str(child.scale)])
	DebugOverlay.log_message("[DEBUG] globe_root transform: %s" % str(_globe_root.global_transform))
	DebugOverlay.log_message("[DEBUG] camera pos: %s" % str(_camera.global_position))

	# DEBUG: Check goldberg data coordinate system.
	if _hex_data.size() > 0:
		var h0: Vector3 = _hex_data[0]["c"] as Vector3
		DebugOverlay.log_message("[DEBUG] hex[0] center=%s (length=%.4f)" % [str(h0), h0.length()])
		# Find hex nearest to known positions.
		for test_name in ["prime_meridian", "india_78E_22N"]:
			var target: Vector3
			if test_name == "prime_meridian":
				# lon=0, lat=0 — should be on Africa
				target = Vector3(-1.0, 0.0, 0.0)  # current formula
			else:
				# India: lon=78E, lat=22N
				var lon_r: float = deg_to_rad(78.0)
				var lat_r: float = deg_to_rad(22.0)
				target = Vector3(-cos(lat_r)*cos(lon_r), sin(lat_r), -cos(lat_r)*sin(lon_r))
			var best_i: int = 0
			var best_d: float = -2.0
			for i in range(_hex_data.size()):
				var d: float = (_hex_data[i]["c"] as Vector3).dot(target)
				if d > best_d:
					best_d = d
					best_i = i
			DebugOverlay.log_message("[DEBUG] nearest hex to %s: idx=%d center=%s dot=%.4f" % [
				test_name, best_i, str(_hex_data[best_i]["c"]), best_d])


func _process(delta: float) -> void:
	_cam_dist = lerpf(_cam_dist, _cam_dist_target, ZOOM_SMOOTH * delta)
	_update_globe()
	_update_camera(delta)

	if _territory_mesh_dirty and _conquest_initialized:
		_rebuild_territory_mesh()
		_rebuild_selection_mesh()
		_rebuild_border_mesh()
		_update_army_labels()
		_update_name_label_visibility()
		_territory_mesh_dirty = false

	if _dice_display_timer > 0.0:
		_dice_display_timer -= delta

	# Setup phase auto-advance.
	if _conquest_initialized and _setup_timer > 0.0:
		_setup_timer -= delta
		if _setup_timer <= 0.0:
			_advance_setup_phase()

	_hud_draw.queue_redraw()


## Called when a setup timer expires (roll display done, AI draft turn, etc).
func _advance_setup_phase() -> void:
	if _cqs == null:
		return
	match _cqs.current_phase:
		ConquestData.ConquestPhase.ROLL_FOR_ORDER:
			# Roll results shown — advance to draft.
			ConquestSpawn.begin_draft(_cqs)
			_log_combat("Territory draft begins! Claim territories in turn order.")
			_territory_mesh_dirty = true
			_update_button_visibility()
			# If first player is AI, auto-draft.
			_try_ai_draft_turn()
		ConquestData.ConquestPhase.TERRITORY_DRAFT:
			_try_ai_draft_turn()
		ConquestData.ConquestPhase.ARMY_PLACEMENT:
			_try_ai_placement_turn()


# ---------------------------------------------------------------------------
# Globe rendering
# ---------------------------------------------------------------------------
func _update_globe() -> void:
	# Static globe — no rotation. All children (overlays, labels) stay aligned.
	_globe_root.quaternion = Quaternion.IDENTITY


func _update_camera(delta: float) -> void:
	# Smoothly slerp toward track target if tracking is active.
	if _cam_tracking and _cam_track_target.length_squared() > 0.01:
		var world_target: Vector3 = (_globe_root.global_transform.basis * _cam_track_target).normalized()
		_cam_dir = _cam_dir.slerp(world_target, 1.0 - exp(-CAM_TRACK_SPEED * delta))
		# Stop tracking once close enough.
		if _cam_dir.dot(world_target) > 0.999:
			_cam_tracking = false

	# Keep up vector pointing toward north pole (Y=up in Godot convention).
	var perp: Vector3 = Vector3.UP - _cam_dir * _cam_dir.dot(Vector3.UP)
	var target_up: Vector3 = perp.normalized() if perp.length_squared() > 1e-4 else Vector3.FORWARD
	_cam_up = _cam_up.slerp(target_up, 1.0 - exp(-CAM_TRACK_SPEED * delta))

	_camera.position = _cam_dir * _cam_dist
	_camera.look_at(Vector3.ZERO, _cam_up)


## Pan the camera to look at a territory.
func _look_at_territory(territory_id: String) -> void:
	if _cqs == null:
		return
	var t: ConquestData.ConquestTerritory = _cqs.territories.get(territory_id)
	if t != null and t.sphere_pos.length_squared() > 0.01:
		_cam_track_target = t.sphere_pos
		_cam_tracking = true


func _apply_globe_texture() -> void:
	var tex := load("res://assets/maps/globe.png") as Texture2D
	if tex == null:
		push_error("[ConquestArena] Cannot load globe.png")
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Unshaded: equal lighting everywhere, no dark side.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_globe_mesh.material_override = mat


func _apply_atmosphere_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.albedo_color = Color(0.35, 0.65, 1.0, 0.10)
	mat.emission_enabled = true
	mat.emission = Color(0.20, 0.50, 0.95)
	mat.emission_energy_multiplier = 0.15
	_atmo_mesh.material_override = mat


func _add_goldberg_overlay() -> void:
	var tex := load("res://assets/maps/goldberg_edges.png") as Texture2D
	if tex == null:
		return
	var shader_code := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D goldberg_tex : hint_default_transparent, filter_linear_mipmap_anisotropic;
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.35;
uniform vec4 edge_color : source_color = vec4(0.6, 0.6, 0.6, 1.0);
void fragment() {
	vec4 s = texture(goldberg_tex, UV);
	ALBEDO = edge_color.rgb;
	ALPHA = s.a * edge_opacity * edge_color.a;
}
"""
	var shader := Shader.new()
	shader.code = shader_code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("goldberg_tex", tex)
	mat.set_shader_parameter("edge_opacity", 0.35)
	mat.set_shader_parameter("edge_color", Color(0.6, 0.6, 0.6, 1.0))

	var mesh := SphereMesh.new()
	mesh.radius = 1.004
	mesh.height = 2.008
	mesh.radial_segments = 128
	mesh.rings = 64

	var node := MeshInstance3D.new()
	node.name = "GoldbergOverlay"
	node.mesh = mesh
	node.material_override = mat
	_globe_root.add_child(node)


# ---------------------------------------------------------------------------
# Goldberg hex data
# ---------------------------------------------------------------------------
func _load_hex_data() -> void:
	var f := FileAccess.open("res://assets/data/goldberg_data.json", FileAccess.READ)
	if f == null:
		push_error("[ConquestArena] Cannot load goldberg_data.json")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[ConquestArena] goldberg_data.json parse failed")
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
	DebugOverlay.log_message("[ConquestArena] Loaded %d goldberg hexes." % _hex_data.size())

	# Load land mask.
	var lf := FileAccess.open("res://assets/data/hex_land_mask.json", FileAccess.READ)
	if lf != null:
		var lm_parsed = JSON.parse_string(lf.get_as_text())
		lf.close()
		if lm_parsed is Array:
			_hex_land_mask.clear()
			for v in lm_parsed:
				_hex_land_mask.append(int(v))
			DebugOverlay.log_message("[ConquestArena] Land mask loaded: %d land hexes." % _hex_land_mask.count(1))
	else:
		push_warning("[ConquestArena] hex_land_mask.json not found — using threshold fallback.")


# ---------------------------------------------------------------------------
# Territory → hex assignment (Voronoi on sphere + land mask from globe texture)
# ---------------------------------------------------------------------------

func _assign_hexes_to_territories() -> void:
	if _cqs == null or _hex_data.is_empty():
		return
	_hex_territory_map.clear()
	_hex_territory_map.resize(_hex_data.size())

	# Clear existing assignments.
	for t in _cqs.territories.values():
		t.hex_indices.clear()

	var assigned_count: int = 0
	var has_land_mask: bool = _hex_land_mask.size() == _hex_data.size()

	for i in range(_hex_data.size()):
		# Skip ocean hexes using land mask (sampled from globe texture).
		if has_land_mask and _hex_land_mask[i] == 0:
			_hex_territory_map[i] = ""
			continue

		# Voronoi: assign to nearest territory center.
		var hex_center: Vector3 = _g2d(_hex_data[i]["c"] as Vector3)
		var best_tid: String = ""
		var best_dot: float = -2.0
		for t in _cqs.territories.values():
			var d: float = hex_center.dot(t.sphere_pos)
			if d > best_dot:
				best_dot = d
				best_tid = t.territory_id

		_hex_territory_map[i] = best_tid
		if not best_tid.is_empty():
			var terr: ConquestData.ConquestTerritory = _cqs.territories.get(best_tid)
			if terr != null:
				terr.hex_indices.append(i)
				assigned_count += 1

	DebugOverlay.log_message("[ConquestArena] Hex assignment: %d/%d hexes on land." % [assigned_count, _hex_data.size()])

	# DEBUG: log territory hex counts and sphere positions for key territories.
	for check_tid in ["india", "alaska", "egypt", "brazil", "eastern_australia"]:
		var ct: ConquestData.ConquestTerritory = _cqs.territories.get(check_tid)
		if ct != null:
			DebugOverlay.log_message("[DEBUG] %s: sphere_pos=%s hex_count=%d" % [
				check_tid, str(ct.sphere_pos), ct.hex_indices.size()])
			# Find nearest goldberg hex center to this territory's sphere_pos.
			if not ct.hex_indices.is_empty():
				var first_hex_idx: int = ct.hex_indices[0]
				var hex_c: Vector3 = _hex_data[first_hex_idx]["c"] as Vector3
				DebugOverlay.log_message("[DEBUG]   first_hex center=%s dot_with_sphere_pos=%.4f" % [
					str(hex_c), hex_c.dot(ct.sphere_pos)])


# ---------------------------------------------------------------------------
# Territory color overlay mesh
# ---------------------------------------------------------------------------
func _setup_territory_overlay() -> void:
	# Use StandardMaterial3D with vertex colors for maximum compatibility.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.no_depth_test = false
	mat.render_priority = 1

	_territory_overlay = MeshInstance3D.new()
	_territory_overlay.name = "TerritoryOverlay"
	_territory_overlay.material_override = mat
	# No scale — vertex offset baked into mesh data at radius 1.02.
	_globe_root.add_child(_territory_overlay)


func _setup_selection_overlay() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.render_priority = 2

	_selection_overlay = MeshInstance3D.new()
	_selection_overlay.name = "SelectionOverlay"
	_selection_overlay.material_override = mat
	_globe_root.add_child(_selection_overlay)


## Transform a goldberg-convention Vector3 to Godot SphereMesh convention.
## Goldberg: X=prime meridian, Y=90E, Z=north pole.
## Godot:    -X=prime meridian, -Z=90E, Y=north pole.
func _g2d(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, v.y)


## Rebuild the territory color mesh from current ownership state.
func _rebuild_territory_mesh() -> void:
	if _cqs == null or _hex_data.is_empty() or _hex_territory_map.is_empty():
		return

	var verts := PackedVector3Array()
	var colors := PackedColorArray()

	for i in range(_hex_data.size()):
		var tid: String = _hex_territory_map[i]
		if tid.is_empty():
			continue
		var t: ConquestData.ConquestTerritory = _cqs.territories.get(tid)
		if t == null:
			continue

		# Base color: continent color for unowned, player color for owned.
		var col: Color = CONTINENT_COLORS.get(t.region_id, UNOWNED_COLOR)
		if t.owner_player_id >= 0:
			var player: ConquestData.ConquestPlayer = _cqs.players.get(t.owner_player_id)
			if player != null:
				# Blend player color with continent color.
				var cc: Color = CONTINENT_COLORS.get(t.region_id, UNOWNED_COLOR)
				col = Color(
					player.color.r * 0.6 + cc.r * 0.4,
					player.color.g * 0.6 + cc.g * 0.4,
					player.color.b * 0.6 + cc.b * 0.4,
					0.85
				)

		# Highlight valid targets during attack/fortify.
		if _cqs.current_phase == ConquestData.ConquestPhase.ATTACK and not _pending_attack_from.is_empty():
			if ConquestTM.are_adjacent(_cqs, _pending_attack_from, tid) and t.owner_player_id != _local_player_id:
				col = VALID_TARGET_COLOR
		elif _cqs.current_phase == ConquestData.ConquestPhase.FORTIFY and not _fortify_source_id.is_empty():
			if ConquestPath.can_fortify(_cqs, _local_player_id, _fortify_source_id, tid):
				col = VALID_TARGET_COLOR

		var poly: PackedVector3Array = _hex_data[i]["p"] as PackedVector3Array
		var n: int = poly.size()
		if n < 3:
			continue
		# Transform goldberg vertices to Godot convention and offset to radius 1.02.
		var center: Vector3 = Vector3.ZERO
		for v in poly:
			center += _g2d(v)
		center = (center / float(n)).normalized() * 1.02

		# Triangle fan — reversed winding for outward-facing with CULL_BACK.
		for j in range(n):
			verts.append(center)
			verts.append(_g2d(poly[(j + 1) % n]) * 1.02)
			verts.append(_g2d(poly[j]) * 1.02)
			colors.append(col)
			colors.append(col)
			colors.append(col)

	if verts.is_empty():
		_territory_overlay.mesh = null
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_territory_overlay.mesh = arr_mesh


## Rebuild the selection highlight mesh for the currently selected territory.
func _rebuild_selection_mesh() -> void:
	if _cqs == null or _selected_territory_id.is_empty():
		_selection_overlay.mesh = null
		return

	var t: ConquestData.ConquestTerritory = _cqs.territories.get(_selected_territory_id)
	if t == null or t.hex_indices.is_empty():
		_selection_overlay.mesh = null
		return

	var col: Color = SELECTION_COLOR
	var verts := PackedVector3Array()
	var colors := PackedColorArray()

	for hex_idx in t.hex_indices:
		if hex_idx < 0 or hex_idx >= _hex_data.size():
			continue
		var poly: PackedVector3Array = _hex_data[hex_idx]["p"] as PackedVector3Array
		var n: int = poly.size()
		if n < 3:
			continue
		var center: Vector3 = Vector3.ZERO
		for v in poly:
			center += _g2d(v)
		center = (center / float(n)).normalized() * 1.025
		for j in range(n):
			verts.append(center)
			verts.append(_g2d(poly[(j + 1) % n]) * 1.025)
			verts.append(_g2d(poly[j]) * 1.025)
			colors.append(col)
			colors.append(col)
			colors.append(col)

	if verts.is_empty():
		_selection_overlay.mesh = null
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_selection_overlay.mesh = arr_mesh


# ---------------------------------------------------------------------------
# Border overlay — lines between territories
# ---------------------------------------------------------------------------
func _setup_border_overlay() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.08, 0.05, 0.03, 0.85)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.render_priority = 3

	_border_overlay = MeshInstance3D.new()
	_border_overlay.name = "BorderOverlay"
	_border_overlay.material_override = mat
	_globe_root.add_child(_border_overlay)


## Border line thickness on the unit sphere.
const BORDER_WIDTH: float = 0.006

func _rebuild_border_mesh() -> void:
	if _cqs == null or _hex_data.is_empty() or _hex_territory_map.is_empty():
		return

	var verts := PackedVector3Array()

	for i in range(_hex_data.size()):
		var tid_a: String = _hex_territory_map[i]
		if tid_a.is_empty():
			continue
		var neighbors: Array = _hex_data[i]["n"]
		var poly_a: PackedVector3Array = _hex_data[i]["p"] as PackedVector3Array

		for ni in neighbors:
			var j: int = int(ni)
			if j <= i:
				continue
			if j >= _hex_territory_map.size():
				continue
			var tid_b: String = _hex_territory_map[j]
			if tid_b.is_empty() or tid_b == tid_a:
				continue
			var poly_b: PackedVector3Array = _hex_data[j]["p"] as PackedVector3Array
			var shared: PackedVector3Array = PackedVector3Array()
			for va in poly_a:
				for vb in poly_b:
					if va.distance_to(vb) < 0.001:
						shared.append(va)
						break
			if shared.size() >= 2:
				# Build a thick quad from the shared edge.
				var p0: Vector3 = _g2d(shared[0]).normalized()
				var p1: Vector3 = _g2d(shared[1]).normalized()
				var edge_dir: Vector3 = (p1 - p0).normalized()
				var normal: Vector3 = ((p0 + p1) * 0.5).normalized()
				var offset: Vector3 = edge_dir.cross(normal).normalized() * BORDER_WIDTH
				var r: float = 1.022
				# Two triangles forming a quad — reversed winding.
				verts.append((p0 + offset) * r)
				verts.append((p1 + offset) * r)
				verts.append((p0 - offset) * r)
				verts.append((p1 + offset) * r)
				verts.append((p1 - offset) * r)
				verts.append((p0 - offset) * r)

	if verts.is_empty():
		_border_overlay.mesh = null
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_border_overlay.mesh = arr_mesh


# ---------------------------------------------------------------------------
# 3D Labels — army counts, territory names, region names
# ---------------------------------------------------------------------------
func _create_territory_labels() -> void:
	for t in _cqs.territories.values():
		# Army count label.
		# Army count label — small, readable circle with number.
		var army_label := Label3D.new()
		army_label.name = "ArmyLabel_" + t.territory_id
		army_label.text = ""
		army_label.font_size = 36
		army_label.pixel_size = 0.0015
		army_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		army_label.no_depth_test = false
		army_label.render_priority = 10
		army_label.modulate = Color(1, 1, 1, 1)
		army_label.outline_modulate = Color(0, 0, 0, 0.95)
		army_label.outline_size = 8
		army_label.position = t.sphere_pos * 1.02
		_globe_root.add_child(army_label)
		_army_labels[t.territory_id] = army_label

		# Territory name label — tiny, only visible when close.
		var name_label := Label3D.new()
		name_label.name = "NameLabel_" + t.territory_id
		name_label.text = t.display_name
		name_label.font_size = 20
		name_label.pixel_size = 0.0008
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.no_depth_test = false
		name_label.render_priority = 9
		name_label.modulate = Color(0.95, 0.93, 0.88, 0.9)
		name_label.outline_modulate = Color(0, 0, 0, 0.85)
		name_label.outline_size = 6
		name_label.position = t.sphere_pos * 1.014
		name_label.visible = false
		_globe_root.add_child(name_label)
		_name_labels[t.territory_id] = name_label


func _create_region_labels() -> void:
	for region in _cqs.regions.values():
		# Compute centroid of region territory positions.
		var centroid := Vector3.ZERO
		var count: int = 0
		for tid in region.territory_ids:
			var t: ConquestData.ConquestTerritory = _cqs.territories.get(tid)
			if t != null:
				centroid += t.sphere_pos
				count += 1
		if count > 0:
			centroid = (centroid / float(count)).normalized()

		var label := Label3D.new()
		label.name = "RegionLabel_" + region.region_id
		label.text = region.display_name
		label.font_size = 24
		label.pixel_size = 0.0012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		label.render_priority = 8
		label.modulate = Color(1.0, 1.0, 0.95, 0.35)
		label.outline_modulate = Color(0, 0, 0, 0.2)
		label.outline_size = 4
		label.position = centroid * 1.035
		_globe_root.add_child(label)
		_region_labels[region.region_id] = label


func _update_army_labels() -> void:
	if _cqs == null:
		return
	for tid in _army_labels.keys():
		var label: Label3D = _army_labels[tid]
		var t: ConquestData.ConquestTerritory = _cqs.territories.get(tid)
		if t == null:
			label.visible = false
			continue
		if t.army_count > 0:
			label.text = str(t.army_count)
			label.visible = true
			if t.owner_player_id >= 0:
				var player: ConquestData.ConquestPlayer = _cqs.players.get(t.owner_player_id)
				if player != null:
					# Show army count in player's color with dark outline for readability.
					label.modulate = player.color
					label.outline_modulate = Color(0, 0, 0, 1)
			else:
				# Neutral — grey.
				label.modulate = Color(0.7, 0.7, 0.7, 1)
				label.outline_modulate = Color(0, 0, 0, 1)
		else:
			label.visible = false

	# Update territory name labels to show owner.
	for tid in _name_labels.keys():
		var name_label: Label3D = _name_labels[tid]
		var t: ConquestData.ConquestTerritory = _cqs.territories.get(tid)
		if t == null:
			continue
		var owner_tag: String = ""
		if t.owner_player_id >= 0:
			var player: ConquestData.ConquestPlayer = _cqs.players.get(t.owner_player_id)
			if player != null:
				owner_tag = " [%s]" % player.display_name
				name_label.modulate = Color(player.color.r * 0.5 + 0.5, player.color.g * 0.5 + 0.5, player.color.b * 0.5 + 0.5, 0.95)
			else:
				name_label.modulate = Color(0.9, 0.88, 0.83, 0.85)
		else:
			name_label.modulate = Color(0.75, 0.73, 0.70, 0.7)
		name_label.text = t.display_name + owner_tag


func _update_name_label_visibility() -> void:
	var show_names: bool = _cam_dist < 3.5
	for label in _name_labels.values():
		(label as Label3D).visible = show_names


# ---------------------------------------------------------------------------
# Terrain type classification
# ---------------------------------------------------------------------------
func _classify_hex_terrain() -> void:
	_hex_terrain_types.clear()
	_hex_terrain_types.resize(_hex_data.size())
	for i in range(_hex_data.size()):
		var tid: String = _hex_territory_map[i] if i < _hex_territory_map.size() else ""
		if not tid.is_empty():
			var t: ConquestData.ConquestTerritory = _cqs.territories.get(tid)
			if t != null:
				var hex_c: Vector3 = _g2d(_hex_data[i]["c"] as Vector3)
				var dot_val: float = hex_c.dot(t.sphere_pos)
				if dot_val > 0.97:
					_hex_terrain_types[i] = ConquestData.TerrainType.LAND
				else:
					_hex_terrain_types[i] = ConquestData.TerrainType.SAND
			else:
				_hex_terrain_types[i] = ConquestData.TerrainType.OCEAN
		else:
			# Unassigned hex — check if near any territory.
			var hex_c: Vector3 = _g2d(_hex_data[i]["c"] as Vector3)
			var best_dot: float = -2.0
			for t in _cqs.territories.values():
				var d: float = hex_c.dot(t.sphere_pos)
				if d > best_dot:
					best_dot = d
			if best_dot > 0.90:
				_hex_terrain_types[i] = ConquestData.TerrainType.OCEAN
			else:
				_hex_terrain_types[i] = ConquestData.TerrainType.DEEP_OCEAN


# ---------------------------------------------------------------------------
# Raycast picking (mouse → globe → hex → territory)
# ---------------------------------------------------------------------------
func _pick_territory_from_mouse(mouse_pos: Vector2) -> String:
	if _camera == null or _hex_data.is_empty() or _cqs == null:
		return ""

	# Ray from camera through mouse position.
	var from: Vector3 = _camera.project_ray_origin(mouse_pos)
	var dir: Vector3 = _camera.project_ray_normal(mouse_pos)

	# Intersect with unit sphere (globe_root is at origin, radius ~1.0).
	# Transform ray into globe_root local space.
	var inv_basis: Basis = _globe_root.global_transform.basis.inverse()
	var inv_origin: Vector3 = _globe_root.global_transform.origin
	var local_from: Vector3 = inv_basis * (from - inv_origin)
	var local_dir: Vector3 = (inv_basis * dir).normalized()

	# Ray-sphere intersection: |local_from + t * local_dir|² = 1
	var a: float = local_dir.dot(local_dir)
	var b: float = 2.0 * local_from.dot(local_dir)
	var c: float = local_from.dot(local_from) - 1.0
	var disc: float = b * b - 4.0 * a * c
	if disc < 0.0:
		return ""  # Miss.

	var t_hit: float = (-b - sqrt(disc)) / (2.0 * a)
	if t_hit < 0.0:
		t_hit = (-b + sqrt(disc)) / (2.0 * a)
	if t_hit < 0.0:
		return ""

	var hit_point: Vector3 = (local_from + local_dir * t_hit).normalized()

	# Find nearest hex to hit point. Transform hex centers to Godot convention.
	var best_idx: int = -1
	var best_dot: float = -2.0
	for i in range(_hex_data.size()):
		var hc: Vector3 = _g2d(_hex_data[i]["c"] as Vector3)
		var d: float = hit_point.dot(hc)
		if d > best_dot:
			best_dot = d
			best_idx = i

	if best_idx < 0 or best_idx >= _hex_territory_map.size():
		return ""

	return _hex_territory_map[best_idx]


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
var _orbit_drag_active: bool = false
var _orbit_drag_prev: Vector2 = Vector2.ZERO
## Left-click drag state: tracks whether the mouse moved (drag vs click).
var _left_down: bool = false
var _left_down_pos: Vector2 = Vector2.ZERO
var _left_dragged: bool = false
const DRAG_THRESHOLD: float = 6.0  # pixels before a click becomes a drag

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_request_quit()
				return
			KEY_F3:
				if _cqs != null:
					ConquestDebug.dump_state(_cqs)
				return

	if not _conquest_initialized:
		return

	# Block globe interaction during roll-for-order screen.
	if _cqs != null and _cqs.current_phase == ConquestData.ConquestPhase.ROLL_FOR_ORDER:
		return

	# Scroll zoom.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist_target = clampf(_cam_dist_target - ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist_target = clampf(_cam_dist_target + ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
			return

	# Right/middle mouse orbit drag.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_orbit_drag_active = event.pressed
			_orbit_drag_prev = event.position
			if event.pressed:
				_cam_tracking = false  # Stop auto-tracking when user manually orbits.
			return

	# Left mouse: click to select territory OR drag to orbit.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_down = true
			_left_down_pos = event.position
			_left_dragged = false
		else:
			# Release — if we didn't drag, it's a click → select territory.
			if _left_down and not _left_dragged:
				var clicked_id: String = _pick_territory_from_mouse(event.position)
				_handle_territory_click(clicked_id)
			_left_down = false
			_left_dragged = false
		return

	if event is InputEventMouseMotion:
		# Orbit from any active drag (left, right, or middle).
		var dragging: bool = _orbit_drag_active
		if _left_down:
			var dist: float = event.position.distance_to(_left_down_pos)
			if dist > DRAG_THRESHOLD:
				_left_dragged = true
			if _left_dragged:
				dragging = true

		if dragging:
			var delta: Vector2 = event.position - _orbit_drag_prev
			_orbit_drag_prev = event.position
			_cam_tracking = false  # Stop auto-tracking during manual orbit.
			# Horizontal orbit around world Y axis.
			var yaw_q := Quaternion(Vector3.UP, -delta.x * 0.004)
			# Vertical tilt around camera right axis (limited to ~40° from equator).
			var right: Vector3 = _camera.global_transform.basis.x
			var pitch_q := Quaternion(right, -delta.y * 0.002)
			_cam_dir = (yaw_q * pitch_q * _cam_dir).normalized()
			_cam_dir.y = clampf(_cam_dir.y, -0.55, 0.55)
			_cam_dir = _cam_dir.normalized()
			return

		# Update drag prev for next frame even when not dragging.
		_orbit_drag_prev = event.position

		# Hover — pick territory under mouse.
		var hovered: String = _pick_territory_from_mouse(event.position)
		if hovered != _hover_territory_id:
			_hover_territory_id = hovered
		return


# ---------------------------------------------------------------------------
# Quit flow
# ---------------------------------------------------------------------------
func _request_quit() -> void:
	if GameManager != null:
		GameManager.reset()
	get_tree().change_scene_to_file(GameManager.HOME_SCREEN_SCENE_PATH if GameManager != null else "res://scenes/screens/home_screen.tscn")


# ---------------------------------------------------------------------------
# UI setup
# ---------------------------------------------------------------------------
func _setup_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UILayer"
	add_child(_ui_layer)

	# HUD draw control — covers the full viewport, draws custom HUD.
	_hud_draw = Control.new()
	_hud_draw.name = "HUDDraw"
	_hud_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_draw.draw.connect(_on_hud_draw)
	_ui_layer.add_child(_hud_draw)

	# End Phase button.
	_end_phase_button = Button.new()
	_end_phase_button.name = "EndPhaseBtn"
	_end_phase_button.text = "End Attack"
	_end_phase_button.size = Vector2(160, 40)
	_end_phase_button.visible = false
	_end_phase_button.pressed.connect(_on_end_phase_pressed)
	_ui_layer.add_child(_end_phase_button)

	# End Turn button.
	_end_turn_button = Button.new()
	_end_turn_button.name = "EndTurnBtn"
	_end_turn_button.text = "End Turn"
	_end_turn_button.size = Vector2(160, 40)
	_end_turn_button.visible = false
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_ui_layer.add_child(_end_turn_button)

	# Game log panel (bottom-left) — scrollable, with dark background.
	var log_panel := PanelContainer.new()
	log_panel.name = "LogPanel"
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_panel.size = Vector2(420, 180)
	log_panel.position = Vector2(12, -192)
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0.06, 0.05, 0.04, 0.88)
	log_style.border_color = Color(0.35, 0.28, 0.20, 0.6)
	log_style.set_border_width_all(1)
	log_style.set_corner_radius_all(6)
	log_style.set_content_margin_all(8)
	log_panel.add_theme_stylebox_override("panel", log_style)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(log_panel)

	var log_scroll := ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.add_child(log_scroll)

	_combat_log_label = Label.new()
	_combat_log_label.name = "CombatLog"
	_combat_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_combat_log_label.add_theme_font_size_override("font_size", 12)
	_combat_log_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80, 0.95))
	_combat_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_combat_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_scroll.add_child(_combat_log_label)

	# Quit button (top-right).
	_quit_button = Button.new()
	_quit_button.name = "QuitBtn"
	_quit_button.text = "Quit Game"
	_quit_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_quit_button.size = Vector2(130, 36)
	_quit_button.position = Vector2(-146, 16)
	_quit_button.pressed.connect(_request_quit)
	_ui_layer.add_child(_quit_button)

	# Next Unclaimed button (shown during draft).
	_next_unclaimed_button = Button.new()
	_next_unclaimed_button.name = "NextUnclaimedBtn"
	_next_unclaimed_button.text = "Find Unclaimed"
	_next_unclaimed_button.size = Vector2(160, 40)
	_next_unclaimed_button.visible = false
	_next_unclaimed_button.pressed.connect(func(): _on_next_unclaimed_pressed())
	_ui_layer.add_child(_next_unclaimed_button)

	# Continue button — used for roll-for-order screen.
	_continue_button = Button.new()
	_continue_button.name = "ContinueBtn"
	_continue_button.text = "Continue"
	_continue_button.size = Vector2(200, 48)
	_continue_button.visible = false
	_continue_button.pressed.connect(_on_continue_pressed)
	_ui_layer.add_child(_continue_button)


# ---------------------------------------------------------------------------
# HUD drawing (on the Control overlay)
# ---------------------------------------------------------------------------
const PLAYER_ICON_RADIUS: float = 14.0
const PLAYER_ROW_HEIGHT: float = 52.0
const TURN_ARROW: String = ">"

func _on_hud_draw() -> void:
	if _cqs == null or not _conquest_initialized:
		return

	var vp: Vector2 = _hud_draw.get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font

	# Position buttons at bottom-center.
	if _end_phase_button != null:
		_end_phase_button.position = Vector2(vp.x * 0.5 - 200, vp.y - 60)
	if _end_turn_button != null:
		_end_turn_button.position = Vector2(vp.x * 0.5 + 30, vp.y - 60)
	if _next_unclaimed_button != null:
		_next_unclaimed_button.position = Vector2(vp.x * 0.5 - 80, vp.y - 60)

	# Roll-for-order is a full-screen overlay — draw ONLY that.
	if _cqs.current_phase == ConquestData.ConquestPhase.ROLL_FOR_ORDER:
		_draw_roll_for_order_screen(vp, font)
		return

	_draw_player_roster(vp, font)
	_draw_phase_hud(vp, font)
	_draw_territory_info(vp, font)
	_draw_dice_display(vp, font)

	if _cqs.current_phase == ConquestData.ConquestPhase.GAME_OVER:
		_draw_game_over_overlay(vp, font)


## ── Left sidebar: player roster with icons and turn indicator ─────────────
func _draw_player_roster(_vp: Vector2, font: Font) -> void:
	var px: float = 12.0
	var py: float = 16.0
	var pw: float = 220.0
	var ph: float = 16.0 + PLAYER_ROW_HEIGHT * _cqs.players.size()

	# Panel background.
	_hud_draw.draw_rect(Rect2(px - 4, py - 4, pw, ph), HUD_BG)
	_hud_draw.draw_rect(Rect2(px - 4, py - 4, pw, ph), HUD_BORDER, false, 1.2)

	var row_y: float = py + 4.0
	for player in _cqs.players.values():
		var is_cur: bool = (player.player_id == _cqs.current_player_id)
		var tc: int = ConquestTM.territory_count(_cqs, player.player_id)
		var pl_col: Color = player.color if player.is_alive else Color(player.color.r, player.color.g, player.color.b, 0.3)

		# Highlight row for current turn.
		if is_cur:
			_hud_draw.draw_rect(Rect2(px - 2, row_y - 2, pw - 4, PLAYER_ROW_HEIGHT - 4), Color(1, 1, 1, 0.08))
			# Turn arrow.
			_hud_draw.draw_string(font, Vector2(px + 2, row_y + 24), TURN_ARROW,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, HUD_ACCENT)

		# Colored circle icon.
		var icon_cx: float = px + 30.0
		var icon_cy: float = row_y + PLAYER_ROW_HEIGHT * 0.5 - 4.0
		_hud_draw.draw_circle(Vector2(icon_cx, icon_cy), PLAYER_ICON_RADIUS, pl_col)
		# Border ring.
		_hud_draw.draw_arc(Vector2(icon_cx, icon_cy), PLAYER_ICON_RADIUS + 1.0, 0.0, TAU, 20,
			Color(1, 1, 1, 0.35) if player.is_alive else Color(1, 1, 1, 0.1), 1.5)
		# Player initial inside circle.
		var initial: String = player.display_name.substr(0, 1).to_upper()
		_hud_draw.draw_string(font, Vector2(icon_cx - 5, icon_cy + 5), initial,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))

		# Name and stats.
		var name_x: float = px + 52.0
		var name_col: Color = Color(1, 1, 1, 0.95) if is_cur else pl_col
		var dead_suffix: String = "  ELIMINATED" if not player.is_alive else ""
		_hud_draw.draw_string(font, Vector2(name_x, row_y + 16), player.display_name + dead_suffix,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, name_col)
		# Territory count + army total.
		var total_armies: int = 0
		for t in _cqs.territories.values():
			if t.owner_player_id == player.player_id:
				total_armies += t.army_count
		_hud_draw.draw_string(font, Vector2(name_x, row_y + 32),
			"%d territories  |  %d armies" % [tc, total_armies],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HUD_TEXT_DIM)

		row_y += PLAYER_ROW_HEIGHT


## ── Top-center: phase banner and action prompt ────────────────────────────
func _draw_phase_hud(vp: Vector2, font: Font) -> void:
	var phase_col: Color = PHASE_COLORS.get(_cqs.current_phase, HUD_ACCENT)
	var cx: float = vp.x * 0.5
	var cur_p: ConquestData.ConquestPlayer = _cqs.players.get(_cqs.current_player_id)

	# Build instruction text.
	var title: String = ""
	var subtitle: String = ""
	var detail: String = ""

	match _cqs.current_phase:
		ConquestData.ConquestPhase.ROLL_FOR_ORDER:
			title = "ROLLING FOR TURN ORDER"
			subtitle = "All players roll a die — highest goes first"
			detail = ""
		ConquestData.ConquestPhase.TERRITORY_DRAFT:
			if _cqs.current_player_id == _local_player_id:
				var unclaimed_count: int = ConquestSpawn.unclaimed_territories(_cqs).size()
				title = "TERRITORY DRAFT  —  %d unclaimed" % unclaimed_count
				subtitle = "Click any unclaimed territory to claim it"
				detail = "Drag to rotate  |  Scroll to zoom  |  Each territory gets 1 army"
			else:
				title = "%s is drafting..." % (cur_p.display_name if cur_p else "?")
				subtitle = "Waiting for their pick"
		ConquestData.ConquestPhase.ARMY_PLACEMENT:
			if _cqs.current_player_id == _local_player_id:
				var pool: int = ConquestSpawn.current_player_pool(_cqs)
				title = "PLACE ARMIES  —  %d remaining" % pool
				subtitle = "Click your territories to reinforce them"
				detail = "Place one army at a time on territories you own"
			else:
				title = "%s is placing armies..." % (cur_p.display_name if cur_p else "?")
				subtitle = "Waiting for opponent"
		ConquestData.ConquestPhase.REINFORCE:
			if _cqs.current_player_id == _local_player_id:
				title = "REINFORCE  —  %d armies to place" % _cqs.reinforcements_remaining
				subtitle = "Click your territories to place armies one at a time"
				detail = "Armies are placed on territories you own (your color)"
			else:
				title = "%s is reinforcing..." % (cur_p.display_name if cur_p else "?")
				subtitle = "Waiting for opponent"
		ConquestData.ConquestPhase.ATTACK:
			if _cqs.current_player_id == _local_player_id:
				if _pending_attack_from.is_empty():
					title = "ATTACK PHASE"
					subtitle = "Click one of your territories with 2+ armies to attack from"
					detail = "Or press End Attack / End Turn to skip"
				else:
					title = "ATTACK  —  from %s" % _territory_name(_pending_attack_from)
					subtitle = "Now click an adjacent enemy territory to attack it"
					detail = "Green-highlighted territories are valid targets  |  Click your own territory to switch"
			else:
				title = "%s is attacking..." % (cur_p.display_name if cur_p else "?")
				subtitle = "Waiting for opponent"
		ConquestData.ConquestPhase.FORTIFY:
			if _cqs.current_player_id == _local_player_id:
				if _cqs.fortify_used:
					title = "FORTIFY COMPLETE"
					subtitle = "Press End Turn to finish your turn"
				elif _fortify_source_id.is_empty():
					title = "FORTIFY PHASE"
					subtitle = "Click a territory with 2+ armies to move troops from"
					detail = "You get one fortify move per turn  |  Or press End Turn"
				else:
					title = "FORTIFY  —  from %s" % _territory_name(_fortify_source_id)
					subtitle = "Click a connected friendly territory to move armies to"
					detail = "Green-highlighted territories are reachable"
			else:
				title = "%s is fortifying..." % (cur_p.display_name if cur_p else "?")
				subtitle = "Waiting for opponent"
		ConquestData.ConquestPhase.GAME_OVER:
			pass  # Handled by game over overlay.

	if title.is_empty():
		return

	# Draw banner — wide enough for text, centered at top.
	var bw: float = maxf(420.0, vp.x * 0.4)
	var bh: float = 72.0 if detail.is_empty() else 88.0
	var bx: float = cx - bw * 0.5
	var by: float = 8.0

	_hud_draw.draw_rect(Rect2(bx, by, bw, bh), HUD_BG)
	_hud_draw.draw_rect(Rect2(bx, by, bw, bh), phase_col * Color(1, 1, 1, 0.5), false, 1.5)

	# Title line.
	_hud_draw.draw_string(font, Vector2(cx, by + 22), title,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 16, phase_col)

	# Subtitle.
	if not subtitle.is_empty():
		_hud_draw.draw_string(font, Vector2(cx, by + 44), subtitle,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, HUD_TEXT)

	# Detail / controls hint.
	if not detail.is_empty():
		_hud_draw.draw_string(font, Vector2(cx, by + 62), detail,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 10, HUD_TEXT_DIM)

	# Turn counter (small, right side of banner).
	_hud_draw.draw_string(font, Vector2(bx + bw - 8, by + 16), "Turn %d" % _cqs.turn_number,
		HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, HUD_TEXT_DIM)


## ── Bottom-left: selected territory details ───────────────────────────────
func _draw_territory_info(vp: Vector2, font: Font) -> void:
	if _selected_territory_id.is_empty() and _hover_territory_id.is_empty():
		return
	var tid: String = _selected_territory_id if not _selected_territory_id.is_empty() else _hover_territory_id
	var t: ConquestData.ConquestTerritory = _cqs.territories.get(tid)
	if t == null:
		return

	var bx: float = vp.x * 0.5 - 160.0
	var by: float = vp.y - 110.0
	var bw: float = 320.0
	var bh: float = 44.0
	_hud_draw.draw_rect(Rect2(bx, by, bw, bh), HUD_BG)
	_hud_draw.draw_rect(Rect2(bx, by, bw, bh), HUD_BORDER, false, 1.0)

	var owner_p: ConquestData.ConquestPlayer = _cqs.players.get(t.owner_player_id)
	var owner_col: Color = owner_p.color if owner_p != null else HUD_TEXT_DIM
	var owner_name: String = owner_p.display_name if owner_p != null else "Neutral"

	# Territory name.
	_hud_draw.draw_string(font, Vector2(bx + 10, by + 16), t.display_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HUD_TEXT)
	# Owner dot + name.
	_hud_draw.draw_circle(Vector2(bx + 10 + 4, by + 32), 4.0, owner_col)
	_hud_draw.draw_string(font, Vector2(bx + 22, by + 36), "%s  |  %d armies" % [owner_name, t.army_count],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HUD_TEXT_DIM)

	# Region info.
	var region: ConquestData.ConquestRegion = _cqs.regions.get(t.region_id)
	if region != null:
		_hud_draw.draw_string(font, Vector2(bx + bw - 10, by + 16),
			"%s (+%d)" % [region.display_name, region.bonus_armies],
			HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, HUD_TEXT_DIM)


## ── Dice roll display ─────────────────────────────────────────────────────
func _draw_dice_display(vp: Vector2, font: Font) -> void:
	if _dice_display_timer <= 0.0 or _dice_display_data.is_empty():
		return

	var alpha: float = clampf(_dice_display_timer / 0.5, 0.0, 1.0)  # fade out last 0.5s
	var cx: float = vp.x * 0.5
	var cy: float = vp.y * 0.5

	# Panel background.
	var pw: float = 300.0
	var ph: float = 120.0
	_hud_draw.draw_rect(Rect2(cx - pw * 0.5, cy - ph * 0.5, pw, ph),
		Color(0.06, 0.05, 0.04, 0.92 * alpha))
	_hud_draw.draw_rect(Rect2(cx - pw * 0.5, cy - ph * 0.5, pw, ph),
		Color(0.6, 0.4, 0.2, 0.8 * alpha), false, 1.5)

	# Title.
	var from_name: String = str(_dice_display_data.get("from", ""))
	var to_name: String = str(_dice_display_data.get("to", ""))
	_hud_draw.draw_string(font, Vector2(cx, cy - ph * 0.5 + 20),
		"%s  ->  %s" % [from_name, to_name],
		HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0.9, 0.9, 0.9, alpha))

	# Attacker dice (red).
	var atk_dice: Array = _dice_display_data.get("atk_dice", [])
	var def_dice: Array = _dice_display_data.get("def_dice", [])
	var die_size: float = 36.0
	var die_gap: float = 6.0

	# Draw attacker dice.
	var atk_start_x: float = cx - 80.0
	var die_y: float = cy - 10.0
	_hud_draw.draw_string(font, Vector2(atk_start_x, die_y - 12), "ATK",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.4, 0.3, alpha))
	for i in range(atk_dice.size()):
		var dx: float = atk_start_x + float(i) * (die_size + die_gap)
		_hud_draw.draw_rect(Rect2(dx, die_y, die_size, die_size),
			Color(0.85, 0.15, 0.1, 0.9 * alpha))
		_hud_draw.draw_rect(Rect2(dx, die_y, die_size, die_size),
			Color(1, 0.3, 0.2, alpha), false, 1.5)
		_hud_draw.draw_string(font, Vector2(dx + die_size * 0.5, die_y + die_size * 0.65),
			str(atk_dice[i]), HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(1, 1, 1, alpha))

	# Draw defender dice (blue).
	var def_start_x: float = cx + 30.0
	_hud_draw.draw_string(font, Vector2(def_start_x, die_y - 12), "DEF",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.5, 0.95, alpha))
	for i in range(def_dice.size()):
		var dx: float = def_start_x + float(i) * (die_size + die_gap)
		_hud_draw.draw_rect(Rect2(dx, die_y, die_size, die_size),
			Color(0.1, 0.2, 0.75, 0.9 * alpha))
		_hud_draw.draw_rect(Rect2(dx, die_y, die_size, die_size),
			Color(0.2, 0.4, 1, alpha), false, 1.5)
		_hud_draw.draw_string(font, Vector2(dx + die_size * 0.5, die_y + die_size * 0.65),
			str(def_dice[i]), HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(1, 1, 1, alpha))

	# Losses.
	var atk_loss: int = int(_dice_display_data.get("atk_loss", 0))
	var def_loss: int = int(_dice_display_data.get("def_loss", 0))
	_hud_draw.draw_string(font, Vector2(atk_start_x, die_y + die_size + 16),
		"-%d lost" % atk_loss, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.95, 0.4, 0.3, alpha))
	_hud_draw.draw_string(font, Vector2(def_start_x, die_y + die_size + 16),
		"-%d lost" % def_loss, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.3, 0.5, 0.95, alpha))

	# Captured flash.
	if _dice_display_data.get("captured", false):
		_hud_draw.draw_string(font, Vector2(cx, cy + ph * 0.5 - 8),
			"TERRITORY CAPTURED!", HORIZONTAL_ALIGNMENT_CENTER, -1, 14,
			Color(1.0, 0.9, 0.2, alpha))


## ── Roll-for-order full-screen overlay ─────────────────────────────────────
func _draw_roll_for_order_screen(vp: Vector2, font: Font) -> void:
	# Full dark backdrop.
	_hud_draw.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.05, 0.08, 0.95))

	var cx: float = vp.x * 0.5
	var cy: float = vp.y * 0.5

	# Title.
	_hud_draw.draw_string(font, Vector2(cx, 80), "ROLL FOR TURN ORDER",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 28, HUD_ACCENT)
	_hud_draw.draw_string(font, Vector2(cx, 110), "Each player rolls one die  —  highest goes first",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 13, HUD_TEXT_DIM)

	# Draw each player's roll result.
	var rolls: Dictionary = _dice_display_data.get("rolls", {})
	var order: Array = _dice_display_data.get("order", [])
	var row_h: float = 72.0
	var total_h: float = row_h * _cqs.players.size()
	var start_y: float = cy - total_h * 0.5

	for i in range(order.size()):
		var pid: int = int(order[i])
		var player: ConquestData.ConquestPlayer = _cqs.players.get(pid)
		if player == null:
			continue

		var ry: float = start_y + float(i) * row_h
		var row_w: float = 420.0
		var rx: float = cx - row_w * 0.5

		# Row background — highlight first place.
		var row_bg: Color = Color(0.15, 0.12, 0.08, 0.6) if i == 0 else Color(0.10, 0.08, 0.06, 0.4)
		_hud_draw.draw_rect(Rect2(rx, ry, row_w, row_h - 4), row_bg)
		_hud_draw.draw_rect(Rect2(rx, ry, row_w, row_h - 4), player.color * Color(1, 1, 1, 0.4), false, 1.5)

		# Turn order number.
		var order_label: String = "#%d" % (i + 1)
		_hud_draw.draw_string(font, Vector2(rx + 16, ry + 28), order_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			HUD_ACCENT if i == 0 else HUD_TEXT_DIM)

		# Player icon.
		var icon_x: float = rx + 65.0
		var icon_y: float = ry + row_h * 0.5 - 4.0
		_hud_draw.draw_circle(Vector2(icon_x, icon_y), 18.0, player.color)
		var initial: String = player.display_name.substr(0, 1).to_upper()
		_hud_draw.draw_string(font, Vector2(icon_x - 6, icon_y + 6), initial,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))

		# Player name.
		_hud_draw.draw_string(font, Vector2(rx + 95, ry + 28), player.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, player.color)

		# Die result — big die square.
		var die_x: float = rx + row_w - 65.0
		var die_y: float = ry + 10.0
		var die_sz: float = 48.0
		var die_col: Color = player.color
		die_col.a = 0.85
		_hud_draw.draw_rect(Rect2(die_x, die_y, die_sz, die_sz), die_col)
		_hud_draw.draw_rect(Rect2(die_x, die_y, die_sz, die_sz), Color(1, 1, 1, 0.5), false, 2.0)
		var roll_val: int = int(rolls.get(pid, 0))
		_hud_draw.draw_string(font, Vector2(die_x + die_sz * 0.5, die_y + die_sz * 0.65),
			str(roll_val), HORIZONTAL_ALIGNMENT_CENTER, -1, 24, Color(1, 1, 1, 1))

		# "FIRST" label for winner.
		if i == 0:
			_hud_draw.draw_string(font, Vector2(rx + row_w - 130, ry + 48), "FIRST",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HUD_ACCENT)

	# Position continue button at bottom-center.
	if _continue_button != null:
		_continue_button.position = Vector2(cx - 100, start_y + total_h + 30)
		_continue_button.size = Vector2(200, 48)


## ── Game over overlay ─────────────────────────────────────────────────────
func _draw_game_over_overlay(vp: Vector2, font: Font) -> void:
	_hud_draw.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.55))
	var winner_p: ConquestData.ConquestPlayer = _cqs.players.get(_cqs.winner_player_id)
	var title: String = "GAME OVER"
	var title_col: Color = Color(0.9, 0.9, 0.9)
	if winner_p != null and _cqs.winner_player_id == _local_player_id:
		title = "VICTORY!"
		title_col = Color(0.30, 0.95, 0.45)
	elif winner_p != null:
		title = "%s WINS" % winner_p.display_name
		title_col = winner_p.color
	_hud_draw.draw_string(font, Vector2(vp.x * 0.5, vp.y * 0.38), title,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 52, title_col)
	_hud_draw.draw_string(font, Vector2(vp.x * 0.5, vp.y * 0.38 + 52),
		"Press Escape to return to menu",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 18, HUD_TEXT_DIM)


# ---------------------------------------------------------------------------
# Conquest initialization
# ---------------------------------------------------------------------------
func _init_conquest() -> void:
	_cqs = ConquestBoard.build()

	var player_colors: Array[Color] = [
		Color(0.22, 0.46, 1.00),
		Color(0.85, 0.20, 0.15),
		Color(0.14, 0.76, 0.32),
		Color(0.92, 0.72, 0.06),
		Color(0.70, 0.22, 0.96),
		Color(0.95, 0.55, 0.15),
	]
	var player_names: Array[String] = [
		"Player", "Crimson Armada", "Emerald Company",
		"Golden Corsairs", "Shadow Navy", "Iron Flotilla",
	]
	var total_players: int = clampi(1 + _ai_player_count, 2, 4)
	_local_player_id = 0

	for i in range(total_players):
		var p := ConquestData.ConquestPlayer.new(
			i,
			player_names[i % player_names.size()],
			player_colors[i % player_colors.size()],
			(i != 0)
		)
		_cqs.players[i] = p

	# Assign goldberg hexes to territories and classify terrain.
	_assign_hexes_to_territories()
	_classify_hex_terrain()

	# Create 3D labels for territories and regions.
	_create_territory_labels()
	_create_region_labels()

	# Phase 1: Roll for turn order.
	var rolls: Dictionary = ConquestSpawn.roll_for_order(_cqs, _combat_obj)
	_dice_display_data = {"roll_for_order": true, "rolls": rolls, "order": _cqs.turn_order}
	# Show the roll screen — player must click Continue to advance.
	if _continue_button != null:
		_continue_button.visible = true
	_log_combat("Rolling for turn order...")
	for pid in _cqs.turn_order:
		var player: ConquestData.ConquestPlayer = _cqs.players.get(pid)
		var pname: String = player.display_name if player else "?"
		_log_combat("  %s rolled %d" % [pname, int(rolls.get(pid, 0))])

	_conquest_initialized = true
	_territory_mesh_dirty = true


# ---------------------------------------------------------------------------
# Click dispatch (identical logic to flat version)
# ---------------------------------------------------------------------------
func _handle_territory_click(territory_id: String) -> void:
	if _cqs == null:
		return
	# Pan camera to clicked territory.
	if not territory_id.is_empty():
		_look_at_territory(territory_id)
	match _cqs.current_phase:
		ConquestData.ConquestPhase.TERRITORY_DRAFT:
			_handle_draft_click(territory_id)
		ConquestData.ConquestPhase.ARMY_PLACEMENT:
			_handle_placement_click(territory_id)
		ConquestData.ConquestPhase.REINFORCE:
			_handle_reinforce_click(territory_id)
		ConquestData.ConquestPhase.ATTACK:
			_handle_attack_click(territory_id)
		ConquestData.ConquestPhase.FORTIFY:
			_handle_fortify_click(territory_id)
	_territory_mesh_dirty = true


## ── Territory Draft click handler ──────────────────────────────────────────
func _handle_draft_click(territory_id: String) -> void:
	if territory_id.is_empty():
		return
	if _cqs.current_player_id != _local_player_id:
		return  # Not your turn.
	var t: ConquestData.ConquestTerritory = _cqs.territories.get(territory_id)
	if t == null or t.owner_player_id >= 0:
		_log_combat("That territory is already claimed.")
		return
	if ConquestSpawn.draft_territory(_cqs, territory_id):
		_log_combat("You claimed %s!" % _territory_name(territory_id))
		_selected_territory_id = territory_id
		_look_at_territory(territory_id)
		_territory_mesh_dirty = true
		_check_draft_complete()
		# Trigger AI turns after a short delay.
		if not ConquestSpawn.is_draft_complete(_cqs):
			_setup_timer = 0.3


func _check_draft_complete() -> void:
	if ConquestSpawn.is_draft_complete(_cqs):
		_log_combat("All territories claimed! Place your remaining armies.")
		ConquestSpawn.begin_placement(_cqs)
		_territory_mesh_dirty = true
		# Start AI placement with a short delay.
		_setup_timer = 0.3


## AI drafts one territory on its turn.
func _try_ai_draft_turn() -> void:
	if _cqs.current_phase != ConquestData.ConquestPhase.TERRITORY_DRAFT:
		return
	var player: ConquestData.ConquestPlayer = _cqs.players.get(_cqs.current_player_id)
	if player == null or not player.is_ai:
		return  # Human's turn — wait for click.

	# AI picks: prefer Australia, then South America, then any unclaimed.
	var unclaimed: Array[String] = ConquestSpawn.unclaimed_territories(_cqs)
	if unclaimed.is_empty():
		_check_draft_complete()
		return
	var choice: String = ConquestAI.choose_start_territory(_cqs, _cqs.current_player_id)
	# Fallback if AI choice is already claimed.
	if not unclaimed.has(choice):
		choice = unclaimed[0]
	ConquestSpawn.draft_territory(_cqs, choice)
	_log_combat("%s claimed %s" % [player.display_name, _territory_name(choice)])
	_territory_mesh_dirty = true
	_check_draft_complete()
	# Chain AI turns with small delay.
	if _cqs.current_phase == ConquestData.ConquestPhase.TERRITORY_DRAFT:
		var next_p: ConquestData.ConquestPlayer = _cqs.players.get(_cqs.current_player_id)
		if next_p != null and next_p.is_ai:
			_setup_timer = 0.15


## ── Army Placement click handler ──────────────────────────────────────────
func _handle_placement_click(territory_id: String) -> void:
	if territory_id.is_empty():
		return
	if _cqs.current_player_id != _local_player_id:
		return
	if ConquestSpawn.current_player_pool(_cqs) <= 0:
		return
	if ConquestSpawn.place_army(_cqs, territory_id):
		_log_combat("Placed army on %s (%d remaining)" % [
			_territory_name(territory_id), ConquestSpawn.current_player_pool(_cqs)])
		_selected_territory_id = territory_id
		_territory_mesh_dirty = true
		_check_placement_complete()
		if not ConquestSpawn.is_placement_complete(_cqs):
			_setup_timer = 0.15
	else:
		_log_combat("You don't own that territory.")


func _check_placement_complete() -> void:
	if ConquestSpawn.is_placement_complete(_cqs):
		_log_combat("Setup complete! The game begins.")
		_start_first_turn()


## AI places one army on its turn.
func _try_ai_placement_turn() -> void:
	if _cqs.current_phase != ConquestData.ConquestPhase.ARMY_PLACEMENT:
		return
	var player: ConquestData.ConquestPlayer = _cqs.players.get(_cqs.current_player_id)
	if player == null or not player.is_ai:
		return
	if ConquestSpawn.current_player_pool(_cqs) <= 0:
		_check_placement_complete()
		return
	# AI places on a border territory (reuse reinforce logic).
	var plan: Dictionary = ConquestAI.plan_reinforce(_cqs, _cqs.current_player_id, 1)
	var placed: bool = false
	for tid in plan.keys():
		if ConquestSpawn.place_army(_cqs, tid):
			placed = true
			break
	if not placed:
		# Fallback: place on any owned territory.
		for t in _cqs.territories.values():
			if t.owner_player_id == _cqs.current_player_id:
				ConquestSpawn.place_army(_cqs, t.territory_id)
				break
	_territory_mesh_dirty = true
	_check_placement_complete()
	# Chain AI placement turns.
	if _cqs.current_phase == ConquestData.ConquestPhase.ARMY_PLACEMENT:
		var next_p: ConquestData.ConquestPlayer = _cqs.players.get(_cqs.current_player_id)
		if next_p != null and next_p.is_ai:
			_setup_timer = 0.05


func _handle_reinforce_click(territory_id: String) -> void:
	if territory_id.is_empty() or _cqs.current_player_id != _local_player_id:
		return
	var t: ConquestData.ConquestTerritory = _cqs.territories.get(territory_id)
	if t == null or t.owner_player_id != _local_player_id:
		_selected_territory_id = ""
		return
	if _cqs.reinforcements_remaining <= 0:
		return
	ConquestTM.add_armies(_cqs, territory_id, 1)
	_cqs.reinforcements_remaining -= 1
	_selected_territory_id = territory_id
	_log_combat("Reinforced %s (%d left)" % [_territory_name(territory_id), _cqs.reinforcements_remaining])
	if _cqs.reinforcements_remaining <= 0:
		_advance_to_attack()
	_territory_mesh_dirty = true


func _handle_attack_click(territory_id: String) -> void:
	if territory_id.is_empty():
		_selected_territory_id = ""
		_pending_attack_from = ""
		return
	if _cqs.current_player_id != _local_player_id:
		return
	var t: ConquestData.ConquestTerritory = _cqs.territories.get(territory_id)
	if t == null:
		return

	if _pending_attack_from.is_empty():
		if t.owner_player_id == _local_player_id and t.army_count >= 2:
			_pending_attack_from = territory_id
			_selected_territory_id = territory_id
			_log_combat("Attack from: %s (%d armies)" % [_territory_name(territory_id), t.army_count])
		else:
			_selected_territory_id = territory_id
	else:
		if territory_id == _pending_attack_from:
			_pending_attack_from = ""
			_selected_territory_id = ""
			return
		if t.owner_player_id == _local_player_id:
			if t.army_count >= 2:
				_pending_attack_from = territory_id
				_selected_territory_id = territory_id
			return
		if not ConquestTM.are_adjacent(_cqs, _pending_attack_from, territory_id):
			_log_combat("Not adjacent to %s." % _territory_name(territory_id))
			return
		_execute_attack(_pending_attack_from, territory_id)
		_pending_attack_from = ""
		_selected_territory_id = ""


func _execute_attack(from_id: String, to_id: String) -> void:
	var result: Dictionary = _combat_obj.apply_attack(_cqs, from_id, to_id)
	if result.is_empty():
		return
	_log_combat("%s->%s  ATK%s vs DEF%s  -A%d/-D%d" % [
		_territory_name(from_id), _territory_name(to_id),
		str(result.get("attacker_dice", [])), str(result.get("defender_dice", [])),
		result.get("attacker_losses", 0), result.get("defender_losses", 0)
	])
	# Show dice display.
	_dice_display_data = {
		"atk_dice": result.get("attacker_dice", []),
		"def_dice": result.get("defender_dice", []),
		"atk_loss": result.get("attacker_losses", 0),
		"def_loss": result.get("defender_losses", 0),
		"captured": result.get("captured", false),
		"from": _territory_name(from_id),
		"to": _territory_name(to_id),
	}
	_dice_display_timer = DICE_DISPLAY_DURATION

	if result.get("captured", false):
		_log_combat("CAPTURED %s! Moved %d armies." % [_territory_name(to_id), result.get("armies_moved", 0)])
		_check_elimination_and_victory()
	_territory_mesh_dirty = true


func _handle_fortify_click(territory_id: String) -> void:
	if territory_id.is_empty():
		_fortify_source_id = ""
		_selected_territory_id = ""
		return
	if _cqs.current_player_id != _local_player_id or _cqs.fortify_used:
		return
	var t: ConquestData.ConquestTerritory = _cqs.territories.get(territory_id)
	if t == null:
		return
	if _fortify_source_id.is_empty():
		if t.owner_player_id == _local_player_id and t.army_count >= 2:
			_fortify_source_id = territory_id
			_selected_territory_id = territory_id
			_log_combat("Fortify from: %s (%d armies)" % [_territory_name(territory_id), t.army_count])
	else:
		if territory_id == _fortify_source_id:
			_fortify_source_id = ""
			_selected_territory_id = ""
			return
		if not ConquestPath.can_fortify(_cqs, _local_player_id, _fortify_source_id, territory_id):
			_log_combat("Cannot fortify to %s." % _territory_name(territory_id))
			return
		var src: ConquestData.ConquestTerritory = _cqs.territories[_fortify_source_id]
		var move: int = src.army_count - 1
		ConquestTM.add_armies(_cqs, _fortify_source_id, -move)
		ConquestTM.add_armies(_cqs, territory_id, move)
		_cqs.fortify_used = true
		_log_combat("Fortified %s -> %s (%d armies)" % [
			_territory_name(_fortify_source_id), _territory_name(territory_id), move])
		_fortify_source_id = ""
		_selected_territory_id = ""
		_territory_mesh_dirty = true


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------
func _on_continue_pressed() -> void:
	if _cqs == null:
		return
	if _cqs.current_phase == ConquestData.ConquestPhase.ROLL_FOR_ORDER:
		if _continue_button != null:
			_continue_button.visible = false
		_advance_setup_phase()


func _on_end_phase_pressed() -> void:
	if _cqs == null:
		return
	if _cqs.current_phase == ConquestData.ConquestPhase.ATTACK:
		_advance_to_fortify()


func _on_end_turn_pressed() -> void:
	if _cqs == null:
		return
	if _cqs.current_phase == ConquestData.ConquestPhase.FORTIFY or _cqs.current_phase == ConquestData.ConquestPhase.ATTACK:
		_end_turn()


func _on_next_unclaimed_pressed() -> void:
	if _cqs == null:
		return
	var unclaimed: Array[String] = ConquestSpawn.unclaimed_territories(_cqs)
	if unclaimed.is_empty():
		_log_combat("All territories have been claimed!")
		_check_draft_complete()
		return
	_unclaimed_cycle_index = _unclaimed_cycle_index % unclaimed.size()
	var tid: String = unclaimed[_unclaimed_cycle_index]
	_selected_territory_id = tid
	_look_at_territory(tid)
	_territory_mesh_dirty = true
	_log_combat("Unclaimed: %s (%d/%d remaining)" % [_territory_name(tid), _unclaimed_cycle_index + 1, unclaimed.size()])
	_unclaimed_cycle_index = (_unclaimed_cycle_index + 1) % unclaimed.size()


# ---------------------------------------------------------------------------
# Phase transitions
# ---------------------------------------------------------------------------
func _start_first_turn() -> void:
	# SETUP_LOCK: validate board before starting gameplay.
	if not _validate_setup():
		_log_combat("SETUP VALIDATION FAILED — check debug overlay (F3)")
		return
	_cqs.turn_number = 1
	_cqs.current_player_id = _cqs.turn_order[0]
	_log_combat("Turn 1 begins — %s reinforces." % (
		_cqs.players[_cqs.turn_order[0]].display_name if _cqs.players.has(_cqs.turn_order[0]) else "?"))
	_begin_reinforce_phase()


## SETUP_LOCK validation: verify board state is correct before gameplay starts.
func _validate_setup() -> bool:
	var errors: PackedStringArray = []

	# Every territory must be owned.
	var unowned_count: int = 0
	for t in _cqs.territories.values():
		if t.owner_player_id < 0:
			unowned_count += 1
		if t.army_count < 1:
			errors.append("Territory '%s' has %d armies (need >= 1)" % [t.display_name, t.army_count])
	if unowned_count > 0:
		errors.append("%d territories still unowned" % unowned_count)

	# Every player must own at least one territory.
	for player in _cqs.players.values():
		var tc: int = ConquestTM.territory_count(_cqs, player.player_id)
		if tc == 0:
			errors.append("Player '%s' owns 0 territories" % player.display_name)

	# All placement pools must be 0.
	for pid in _cqs.army_placement_pools.keys():
		var pool: int = int(_cqs.army_placement_pools[pid])
		if pool > 0:
			errors.append("Player %d still has %d armies unplaced" % [pid, pool])

	# Total army count on map must equal sum of starting pools.
	var total_armies_on_map: int = 0
	for t in _cqs.territories.values():
		total_armies_on_map += t.army_count
	var expected_total: int = ConquestData.STARTING_ARMIES_BY_PLAYER_COUNT.get(_cqs.players.size(), 30) * _cqs.players.size()
	if total_armies_on_map != expected_total:
		errors.append("Total armies on map: %d, expected: %d" % [total_armies_on_map, expected_total])

	if errors.is_empty():
		DebugOverlay.log_message("[ConquestArena] SETUP_LOCK validation: PASS")
		return true
	else:
		for e in errors:
			DebugOverlay.log_message("[ConquestArena] SETUP_LOCK ERROR: %s" % e, true)
		return false


func _begin_reinforce_phase() -> void:
	_cqs.current_phase = ConquestData.ConquestPhase.REINFORCE
	_cqs.attack_phase_ended = false
	_cqs.fortify_used = false
	_selected_territory_id = ""
	_pending_attack_from = ""
	_fortify_source_id = ""

	var pid: int = _cqs.current_player_id
	_cqs.reinforcements_remaining = ConquestTM.calculate_reinforcements(_cqs, pid)

	var player: ConquestData.ConquestPlayer = _cqs.players.get(pid)
	var pname: String = player.display_name if player else "?"
	_log_combat("[REINFORCE] %s — %d armies" % [pname, _cqs.reinforcements_remaining])
	_update_button_visibility()
	_territory_mesh_dirty = true

	if player != null and player.is_ai:
		_ai_do_reinforce()


func _advance_to_attack() -> void:
	_cqs.current_phase = ConquestData.ConquestPhase.ATTACK
	_selected_territory_id = ""
	_pending_attack_from = ""
	_update_button_visibility()
	_territory_mesh_dirty = true

	var player: ConquestData.ConquestPlayer = _cqs.players.get(_cqs.current_player_id)
	if player != null and player.is_ai:
		_ai_do_attack()


func _advance_to_fortify() -> void:
	_cqs.current_phase = ConquestData.ConquestPhase.FORTIFY
	_selected_territory_id = ""
	_pending_attack_from = ""
	_update_button_visibility()
	_territory_mesh_dirty = true

	var player: ConquestData.ConquestPlayer = _cqs.players.get(_cqs.current_player_id)
	if player != null and player.is_ai:
		_ai_do_fortify()
		if _cqs.current_phase != ConquestData.ConquestPhase.GAME_OVER:
			_end_turn()


func _end_turn() -> void:
	_cqs.current_phase = ConquestData.ConquestPhase.TURN_END
	_selected_territory_id = ""
	_pending_attack_from = ""
	_fortify_source_id = ""

	var order: Array[int] = _cqs.turn_order
	var idx: int = order.find(_cqs.current_player_id)
	var next_idx: int = (idx + 1) % order.size()
	var attempts: int = 0
	while attempts < order.size():
		var next_pid: int = order[next_idx]
		var next_player: ConquestData.ConquestPlayer = _cqs.players.get(next_pid)
		if next_player != null and next_player.is_alive:
			break
		next_idx = (next_idx + 1) % order.size()
		attempts += 1
	if (next_idx <= idx) and attempts < order.size():
		_cqs.turn_number += 1
	_cqs.current_player_id = order[next_idx]
	_begin_reinforce_phase()


# ---------------------------------------------------------------------------
# AI turn execution
# ---------------------------------------------------------------------------
func _ai_do_reinforce() -> void:
	var pid: int = _cqs.current_player_id
	var plan: Dictionary = ConquestAI.plan_reinforce(_cqs, pid, _cqs.reinforcements_remaining)
	for tid in plan.keys():
		ConquestTM.add_armies(_cqs, tid, int(plan[tid]))
	_cqs.reinforcements_remaining = 0
	_advance_to_attack()


func _ai_do_attack() -> void:
	var pid: int = _cqs.current_player_id
	for _attempt in range(10):
		var attacks: Array[Dictionary] = ConquestAI.plan_attacks(_cqs, pid)
		if attacks.is_empty():
			break
		var attack: Dictionary = attacks[0]
		var from_id: String = str(attack.get("from", ""))
		var to_id: String = str(attack.get("to", ""))
		if from_id.is_empty() or to_id.is_empty():
			break
		var from_t: ConquestData.ConquestTerritory = _cqs.territories.get(from_id)
		if from_t == null or from_t.army_count < 2:
			break
		_execute_attack(from_id, to_id)
		_check_elimination_and_victory()
		if _cqs.current_phase == ConquestData.ConquestPhase.GAME_OVER:
			return
	if _cqs.current_phase != ConquestData.ConquestPhase.GAME_OVER:
		_advance_to_fortify()


func _ai_do_fortify() -> void:
	var pid: int = _cqs.current_player_id
	var plan: Dictionary = ConquestAI.plan_fortify(_cqs, pid)
	if plan.is_empty():
		return
	var from_id: String = str(plan.get("from", ""))
	var to_id: String = str(plan.get("to", ""))
	var armies: int = int(plan.get("armies", 0))
	if from_id.is_empty() or to_id.is_empty() or armies < 1:
		return
	if not ConquestPath.can_fortify(_cqs, pid, from_id, to_id):
		return
	ConquestTM.add_armies(_cqs, from_id, -armies)
	ConquestTM.add_armies(_cqs, to_id, armies)
	_cqs.fortify_used = true
	_log_combat("AI fortified %s -> %s (%d)" % [_territory_name(from_id), _territory_name(to_id), armies])
	_territory_mesh_dirty = true


# ---------------------------------------------------------------------------
# Elimination and victory
# ---------------------------------------------------------------------------
func _check_elimination_and_victory() -> void:
	var eliminated: Array[int] = ConquestTM.check_eliminations(_cqs)
	for pid in eliminated:
		var player: ConquestData.ConquestPlayer = _cqs.players.get(pid)
		if player != null:
			player.is_alive = false
			_log_combat("%s has been eliminated!" % player.display_name)
			_cqs.turn_order.erase(pid)
	var winner: int = ConquestTM.check_winner(_cqs)
	if winner >= 0:
		_cqs.winner_player_id = winner
		_cqs.current_phase = ConquestData.ConquestPhase.GAME_OVER
		var wp: ConquestData.ConquestPlayer = _cqs.players.get(winner)
		_log_combat("GAME OVER — %s wins!" % (wp.display_name if wp != null else "Unknown"))
		_update_button_visibility()
		_territory_mesh_dirty = true


# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
func _update_button_visibility() -> void:
	var phase: int = _cqs.current_phase if _cqs != null else -1
	var is_local_turn: bool = (_cqs != null and _cqs.current_player_id == _local_player_id)
	if _end_phase_button != null:
		_end_phase_button.visible = (phase == ConquestData.ConquestPhase.ATTACK and is_local_turn)
	if _end_turn_button != null:
		_end_turn_button.visible = (
			is_local_turn and
			(phase == ConquestData.ConquestPhase.ATTACK or phase == ConquestData.ConquestPhase.FORTIFY)
		)
	if _next_unclaimed_button != null:
		_next_unclaimed_button.visible = (phase == ConquestData.ConquestPhase.TERRITORY_DRAFT and is_local_turn)


func _log_combat(line: String) -> void:
	_combat_log.append(line)
	if _combat_log.size() > COMBAT_LOG_MAX:
		_combat_log = _combat_log.slice(_combat_log.size() - COMBAT_LOG_MAX)
	if _combat_log_label != null:
		_combat_log_label.text = "\n".join(_combat_log)


func _territory_name(tid: String) -> String:
	if _cqs == null:
		return tid
	var t: ConquestData.ConquestTerritory = _cqs.territories.get(tid)
	return t.display_name if t != null else tid
