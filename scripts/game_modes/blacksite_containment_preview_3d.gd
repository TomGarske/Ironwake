extends Node3D

const MapProfile := preload("res://scripts/shared/blacksite_map_profile.gd")

const CELL_SIZE: float = 2.0
const WALL_HEIGHT: float = 4.2
const WALL_THICK: float = 1.0
const BUILDING_HEIGHT: float = 3.6

@onready var geometry_root: Node3D = $Geometry

func _ready() -> void:
	_build_preview_geometry()

func _build_preview_geometry() -> void:
	for child in geometry_root.get_children():
		child.queue_free()

	var data: Dictionary = MapProfile.build_area51_surface_map()
	var layout: Dictionary = data.get("layout", {})

	var map_w: int = int(layout.get("map_width", MapProfile.MAP_WIDTH))
	var map_h: int = int(layout.get("map_height", MapProfile.MAP_HEIGHT))
	var building_x: int = int(layout.get("building_x", 0))
	var building_y: int = int(layout.get("building_y", 0))
	var building_w: int = int(layout.get("building_w", MapProfile.BUILDING_W))
	var building_h: int = int(layout.get("building_h", MapProfile.BUILDING_H))

	var ring_left: int = int(layout.get("ring_left", 0))
	var ring_top: int = int(layout.get("ring_top", 0))
	var ring_right: int = int(layout.get("ring_right", 0))
	var ring_bottom: int = int(layout.get("ring_bottom", 0))
	var gate_center: int = int(layout.get("gate_center", floori(float(ring_left + ring_right) * 0.5)))
	var gate_half: int = floori(float(MapProfile.GATE_WIDTH) * 0.5)

	var sand_mat := _make_mat(Color(0.86, 0.78, 0.62, 1.0), 0.92, 0.04)
	var metal_mat := _make_mat(Color(0.52, 0.58, 0.64, 1.0), 0.36, 0.72)
	var building_mat := _make_mat(Color(0.38, 0.43, 0.48, 1.0), 0.30, 0.80)
	var accent_mat := _make_emissive_mat(Color(1.0, 0.48, 0.20, 1.0), 1.8)

	# Ground plane.
	var floor_mesh_instance := MeshInstance3D.new()
	floor_mesh_instance.mesh = PlaneMesh.new()
	(floor_mesh_instance.mesh as PlaneMesh).size = Vector2(map_w * CELL_SIZE, map_h * CELL_SIZE)
	floor_mesh_instance.material_override = sand_mat
	floor_mesh_instance.position = Vector3(0.0, 0.0, 0.0)
	geometry_root.add_child(floor_mesh_instance)

	# Central base building.
	_create_box(
		"CentralBuilding",
		Vector3(building_w * CELL_SIZE, BUILDING_HEIGHT, building_h * CELL_SIZE),
		_tile_rect_center(building_x, building_y, building_w, building_h, map_w, map_h) + Vector3(0.0, BUILDING_HEIGHT * 0.5, 0.0),
		building_mat
	)

	# Ring walls (raised).
	var ring_len_x: int = ring_right - ring_left + 1
	var ring_len_y: int = ring_bottom - ring_top + 1

	_create_box(
		"RingNorth",
		Vector3(ring_len_x * CELL_SIZE, WALL_HEIGHT, WALL_THICK),
		_tile_rect_center(ring_left, ring_top, ring_len_x, 1, map_w, map_h) + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0),
		metal_mat
	)
	_create_box(
		"RingWest",
		Vector3(WALL_THICK, WALL_HEIGHT, (ring_len_y - 2) * CELL_SIZE),
		_tile_rect_center(ring_left, ring_top + 1, 1, ring_len_y - 2, map_w, map_h) + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0),
		metal_mat
	)
	_create_box(
		"RingEast",
		Vector3(WALL_THICK, WALL_HEIGHT, (ring_len_y - 2) * CELL_SIZE),
		_tile_rect_center(ring_right, ring_top + 1, 1, ring_len_y - 2, map_w, map_h) + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0),
		metal_mat
	)

	# South wall split around gate opening.
	var gate_left_x: int = gate_center - gate_half
	var gate_right_x: int = gate_center + gate_half
	var south_left_len: int = max(0, gate_left_x - ring_left)
	var south_right_len: int = max(0, ring_right - gate_right_x)

	if south_left_len > 0:
		_create_box(
			"RingSouthLeft",
			Vector3(south_left_len * CELL_SIZE, WALL_HEIGHT, WALL_THICK),
			_tile_rect_center(ring_left, ring_bottom, south_left_len, 1, map_w, map_h) + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0),
			metal_mat
		)
	if south_right_len > 0:
		_create_box(
			"RingSouthRight",
			Vector3(south_right_len * CELL_SIZE, WALL_HEIGHT, WALL_THICK),
			_tile_rect_center(gate_right_x + 1, ring_bottom, south_right_len, 1, map_w, map_h) + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0),
			metal_mat
		)

	# Gate pylons and lintel accent.
	_create_box(
		"GatePylonLeft",
		Vector3(WALL_THICK * 1.2, WALL_HEIGHT + 1.4, WALL_THICK * 1.2),
		_tile_rect_center(gate_left_x - 1, ring_bottom, 1, 1, map_w, map_h) + Vector3(0.0, (WALL_HEIGHT + 1.4) * 0.5, 0.0),
		metal_mat
	)
	_create_box(
		"GatePylonRight",
		Vector3(WALL_THICK * 1.2, WALL_HEIGHT + 1.4, WALL_THICK * 1.2),
		_tile_rect_center(gate_right_x + 1, ring_bottom, 1, 1, map_w, map_h) + Vector3(0.0, (WALL_HEIGHT + 1.4) * 0.5, 0.0),
		metal_mat
	)
	_create_box(
		"GateLintel",
		Vector3((MapProfile.GATE_WIDTH + 2) * CELL_SIZE, 0.26, 0.26),
		_tile_rect_center(gate_left_x - 1, ring_bottom, MapProfile.GATE_WIDTH + 2, 1, map_w, map_h) + Vector3(0.0, WALL_HEIGHT + 1.05, 0.0),
		accent_mat
	)

func _tile_rect_center(tx: int, ty: int, tw: int, th: int, map_w: int, map_h: int) -> Vector3:
	var cx: float = (float(tx) + float(tw) * 0.5 - float(map_w) * 0.5) * CELL_SIZE
	var cz: float = (float(ty) + float(th) * 0.5 - float(map_h) * 0.5) * CELL_SIZE
	return Vector3(cx, 0.0, cz)

func _create_box(node_name: String, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var box := MeshInstance3D.new()
	box.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = mat
	box.position = pos
	geometry_root.add_child(box)

func _make_mat(albedo: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

func _make_emissive_mat(albedo: Color, energy: float) -> StandardMaterial3D:
	var mat := _make_mat(albedo, 0.18, 0.72)
	mat.emission_enabled = true
	mat.emission = albedo
	mat.emission_energy_multiplier = energy
	return mat
