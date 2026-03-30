extends Node3D

const MapProfile := preload("res://scripts/shared/blacksite_map_profile.gd")

const CELL_SIZE: float = 2.0

@onready var geometry_root: Node3D = $Geometry

func _ready() -> void:
	_build_preview_geometry()

func _build_preview_geometry() -> void:
	for child in geometry_root.get_children():
		child.queue_free()

	var data: Dictionary = MapProfile.build_open_sea_map()
	var layout: Dictionary = data.get("layout", {})
	var map_w: int = int(layout.get("map_width", MapProfile.MAP_WIDTH))
	var map_h: int = int(layout.get("map_height", MapProfile.MAP_HEIGHT))

	var water_mat := _make_mat(Color(0.16, 0.42, 0.62, 1.0), 0.12, 0.08)

	var floor_mesh_instance := MeshInstance3D.new()
	floor_mesh_instance.mesh = PlaneMesh.new()
	(floor_mesh_instance.mesh as PlaneMesh).size = Vector2(map_w * CELL_SIZE, map_h * CELL_SIZE)
	floor_mesh_instance.material_override = water_mat
	floor_mesh_instance.position = Vector3.ZERO
	geometry_root.add_child(floor_mesh_instance)

func _make_mat(albedo: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = metallic
	return mat
