extends Node2D

## Draws creature tokens as pie-wedge slices on occupied hexes.

const TOKEN_RADIUS := 20.0


func _draw() -> void:
	var occupied := HexOccupancyValidator.get_all_occupied_hexes()
	var sg := get_parent() as StrategyGame
	if not sg:
		return
	for hex: Vector2i in occupied:
		var wedges := HexOccupancyValidator.get_wedge_layout(hex)
		if wedges.is_empty():
			continue
		var world_center: Vector2 = sg.hex_to_world(hex)
		# Convert from parent (StrategyGame Node2D) local space to this node's local space
		var local_center := to_local(sg.to_global(world_center))
		for w: Dictionary in wedges:
			var cid: String = w.get("creature_id", "")
			var pdata: Dictionary = GameState.placed_creatures.get(cid, {})
			if pdata.is_empty():
				continue
			var color: Color = pdata.get("color", Color.WHITE)
			var start_deg: float = w.get("start_angle", 0.0)
			var end_deg: float = w.get("end_angle", 360.0)
			_draw_wedge(local_center, TOKEN_RADIUS, start_deg, end_deg, color)


func _draw_wedge(center: Vector2, radius: float, start_deg: float, end_deg: float,
		color: Color) -> void:
	var start_rad := deg_to_rad(start_deg)
	var end_rad   := deg_to_rad(end_deg)
	var span_rad  := end_rad - start_rad
	if span_rad <= 0.0:
		return

	# Build polygon for the pie slice
	var points: PackedVector2Array = PackedVector2Array()
	points.append(center)
	var steps: int = maxi(6, int(span_rad / deg_to_rad(10.0)) + 1)
	for i in range(steps + 1):
		var angle := start_rad + span_rad * (float(i) / float(steps))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	draw_colored_polygon(points, color)
	# Draw border lines
	draw_line(center, points[1], Color.BLACK, 1.0)
	draw_line(center, points[points.size() - 1], Color.BLACK, 1.0)
