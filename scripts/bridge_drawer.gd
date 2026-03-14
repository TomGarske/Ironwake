extends Node2D

# Bridge drawer node that handles the actual drawing
var bridge_points: Array[Vector2] = []
var time: float = 0.0

func set_bridge_data(points: Array[Vector2], current_time: float) -> void:
	bridge_points = points
	time = current_time

func _ready() -> void:
	# Make sure we're visible
	visible = true
	z_index = -100

func _draw() -> void:
	if bridge_points.size() < 2:
		# Draw a test circle to verify drawing works
		draw_circle(Vector2(100, 100), 20, Color.RED)
		return
	
	print("[BridgeDrawer] Drawing bridge with ", bridge_points.size(), " points")
	
	# Draw bridge structure
	var bridge_color = Color(0.3, 0.25, 0.2)  # Dark brown/stone
	var highlight_color = Color(0.5, 0.4, 0.3)
	
	# Draw main bridge deck
	var deck_thickness = 12.0
	draw_line(bridge_points[0], bridge_points[1], bridge_color, deck_thickness)
	draw_line(bridge_points[0], bridge_points[1], highlight_color, 2.0)
	
	# Draw supports
	for i in range(2, bridge_points.size() - 1, 2):
		if i + 1 < bridge_points.size():
			var support_start = bridge_points[0] + Vector2((i - 2) * (bridge_points[1].x - bridge_points[0].x) / 4.0, 0)
			var support_end = bridge_points[i]
			draw_line(support_start, support_end, bridge_color, 8.0)
			draw_line(support_start, support_end, highlight_color, 1.0)
	
	# Draw burning/charred effect on bridge
	var burn_intensity = sin(time * 3.0) * 0.3 + 0.7
	var burn_color = Color(0.2, 0.1, 0.05, burn_intensity * 0.5)
	for i in range(0, bridge_points.size() - 1):
		var p1 = bridge_points[i]
		var p2 = bridge_points[i + 1] if i + 1 < bridge_points.size() else bridge_points[0]
		draw_line(p1, p2, burn_color, 6.0)
	
	# Add some glowing embers
	for i in range(8):
		var t = (time * 0.5 + i * 0.3) % 1.0
		var x = lerp(bridge_points[0].x, bridge_points[1].x, t)
		var y = bridge_points[0].y + sin(time * 2.0 + i) * 5.0
		var ember_size = 2.0 + sin(time * 4.0 + i) * 1.0
		var ember_color = Color(1.0, 0.4, 0.0, 0.6)
		draw_circle(Vector2(x, y), ember_size, ember_color)
