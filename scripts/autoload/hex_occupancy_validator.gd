extends Node

## Tracks which creatures occupy which hexes and how many wedge slices they hold.
## A hex has 6 slices total; each creature occupies slice_count slices based on physical size.

# _occupancy: Vector2i → Array[{creature_id: String, slice_count: int}]
var _occupancy: Dictionary = {}


func get_occupied_slices(hex_coords: Vector2i) -> int:
	var entries: Array = _occupancy.get(hex_coords, [])
	var total := 0
	for e: Dictionary in entries:
		total += int(e.get("slice_count", 1))
	return total


func can_place(hex_coords: Vector2i, slice_count: int) -> bool:
	return get_occupied_slices(hex_coords) + slice_count <= 6


func place_creature(hex_coords: Vector2i, creature_id: String, slice_count: int) -> bool:
	if not can_place(hex_coords, slice_count):
		return false
	if not _occupancy.has(hex_coords):
		_occupancy[hex_coords] = []
	_occupancy[hex_coords].append({"creature_id": creature_id, "slice_count": slice_count})
	return true


func remove_creature(creature_id: String, hex_coords: Vector2i) -> void:
	if not _occupancy.has(hex_coords):
		return
	var entries: Array = _occupancy[hex_coords]
	var new_entries: Array = entries.filter(
		func(e: Dictionary) -> bool: return e.get("creature_id", "") != creature_id
	)
	if new_entries.is_empty():
		_occupancy.erase(hex_coords)
	else:
		_occupancy[hex_coords] = new_entries


func can_move(creature_id: String, from_hex: Vector2i, to_hex: Vector2i,
		movement_types: Array[String]) -> bool:
	# Must be able to enter terrain at destination
	var to_terrain := ""
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		for sn: Node in tree.get_nodes_in_group("strategy_game"):
			var sg := sn as StrategyGame
			if sg:
				to_terrain = sg.get_terrain_at(to_hex)
			break
	if to_terrain.is_empty():
		return false
	if not TerrainMovementRules.can_enter(movement_types, to_terrain):
		return false
	# Need slice capacity at destination
	var slice_count := 1
	for entry: Dictionary in _occupancy.get(from_hex, []):
		if entry.get("creature_id", "") == creature_id:
			slice_count = int(entry.get("slice_count", 1))
			break
	return can_place(to_hex, slice_count)


func move_creature(creature_id: String, from_hex: Vector2i, to_hex: Vector2i) -> bool:
	var slice_count := 1
	for entry: Dictionary in _occupancy.get(from_hex, []):
		if entry.get("creature_id", "") == creature_id:
			slice_count = int(entry.get("slice_count", 1))
			break
	remove_creature(creature_id, from_hex)
	return place_creature(to_hex, creature_id, slice_count)


func get_wedge_layout(hex_coords: Vector2i) -> Array:
	var entries: Array = _occupancy.get(hex_coords, [])
	var result: Array = []
	var current_angle := 0.0
	for e: Dictionary in entries:
		var sc: int = int(e.get("slice_count", 1))
		var span := (float(sc) / 6.0) * 360.0
		result.append({
			"creature_id": e.get("creature_id", ""),
			"slice_count": sc,
			"start_angle": current_angle,
			"end_angle":   current_angle + span,
		})
		current_angle += span
	return result


func get_all_occupied_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key: Vector2i in _occupancy.keys():
		result.append(key)
	return result
