extends Control

# ---------------------------------------------------------------------------
# Burning Bridge Background Animation
# ---------------------------------------------------------------------------

var _flame_particles: Array[CPUParticles2D] = []
var _bridge_points: Array[Vector2] = []
var _time: float = 0.0
var _flame_base_positions: Array[Vector2] = []

func _init() -> void:
	print("[BurningBridge] Script initialized!")

func _ready() -> void:
	print("[BurningBridge] _ready() called!")
	
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -100  # Behind everything
	visible = true
	
	# Ensure full screen coverage
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# Force immediate test draw
	queue_redraw()
	
	print("[BurningBridge] Ready. Size: ", size, " Visible: ", visible, " Z-index: ", z_index)
	
	# Wait for viewport to be ready
	await get_tree().process_frame
	print("[BurningBridge] After await, setting up bridge...")
	call_deferred("_setup_bridge")
	call_deferred("_setup_flames")

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()  # Redraw every frame
	_update_flames()

func _draw() -> void:
	print("[BurningBridge] _draw() called! Time: ", _time, " Size: ", size)
	
	# Use the control's own size (should be full screen)
	var draw_size = size
	if draw_size.x == 0 or draw_size.y == 0:
		draw_size = get_viewport_rect().size
		print("[BurningBridge] Using viewport size: ", draw_size)
	
	if draw_size.x == 0 or draw_size.y == 0:
		print("[BurningBridge] Size is zero, skipping draw")
		return
	
	# Draw a test background rectangle covering the entire control - make it VERY visible
	draw_rect(Rect2(0, 0, draw_size.x, draw_size.y), Color(0.4, 0.2, 0.1, 1.0))
	
	# Always draw multiple big test circles to verify drawing works
	draw_circle(Vector2(draw_size.x * 0.5, draw_size.y * 0.5), 200, Color(1, 0.5, 0, 1.0))
	draw_circle(Vector2(150, 150), 80, Color(0, 1, 0, 1.0))
	draw_circle(Vector2(draw_size.x - 150, 150), 80, Color(0, 0, 1, 1.0))
	
	if _bridge_points.size() < 2:
		print("[BurningBridge] Bridge points not set yet, drawing test only")
		return
	
	print("[BurningBridge] Drawing bridge with ", _bridge_points.size(), " points")
	
	# Draw bridge structure
	var bridge_color = Color(0.4, 0.3, 0.25)  # Dark brown/stone (brighter for visibility)
	var highlight_color = Color(0.6, 0.5, 0.4)
	
	# Draw main bridge deck
	var deck_thickness = 15.0
	draw_line(_bridge_points[0], _bridge_points[1], bridge_color, deck_thickness)
	draw_line(_bridge_points[0], _bridge_points[1], highlight_color, 3.0)
	
	# Draw supports
	for i in range(2, _bridge_points.size() - 1, 2):
		if i + 1 < _bridge_points.size():
			var support_start = _bridge_points[0] + Vector2((i - 2) * (_bridge_points[1].x - _bridge_points[0].x) / 4.0, 0)
			var support_end = _bridge_points[i]
			draw_line(support_start, support_end, bridge_color, 10.0)
			draw_line(support_start, support_end, highlight_color, 2.0)
	
	# Draw burning/charred effect on bridge
	var burn_intensity = sin(_time * 3.0) * 0.3 + 0.7
	var burn_color = Color(0.3, 0.15, 0.1, burn_intensity * 0.6)
	for i in range(0, _bridge_points.size() - 1):
		var p1 = _bridge_points[i]
		var p2 = _bridge_points[i + 1] if i + 1 < _bridge_points.size() else _bridge_points[0]
		draw_line(p1, p2, burn_color, 8.0)
	
	# Add some glowing embers
	for i in range(8):
		var t = (_time * 0.5 + i * 0.3) % 1.0
		var x = lerp(_bridge_points[0].x, _bridge_points[1].x, t)
		var y = _bridge_points[0].y + sin(_time * 2.0 + i) * 5.0
		var ember_size = 3.0 + sin(_time * 4.0 + i) * 2.0
		var ember_color = Color(1.0, 0.5, 0.0, 0.8)
		draw_circle(Vector2(x, y), ember_size, ember_color)

func _setup_bridge() -> void:
	# Create bridge structure points (simple arch/bridge shape)
	var viewport_size = get_viewport_rect().size
	if viewport_size.x == 0 or viewport_size.y == 0:
		# Viewport not ready yet, try again next frame
		call_deferred("_setup_bridge")
		return
	
	print("[BurningBridge] Setting up bridge. Viewport size: ", viewport_size)
	
	var center_y = viewport_size.y * 0.7  # Position bridge in lower portion
	var bridge_width = viewport_size.x * 0.8
	var bridge_height = 80.0
	var start_x = viewport_size.x * 0.1
	var end_x = start_x + bridge_width
	
	# Bridge deck (horizontal line)
	_bridge_points = [
		Vector2(start_x, center_y),
		Vector2(end_x, center_y)
	]
	
	# Add some arch supports (vertical lines)
	_bridge_points.append_array([
		Vector2(start_x, center_y + bridge_height),
		Vector2(start_x + bridge_width * 0.25, center_y + bridge_height * 0.6),
		Vector2(start_x + bridge_width * 0.5, center_y + bridge_height * 0.4),
		Vector2(start_x + bridge_width * 0.75, center_y + bridge_height * 0.6),
		Vector2(end_x, center_y + bridge_height)
	])
	
	print("[BurningBridge] Bridge points set: ", _bridge_points.size(), " points")

func _create_flame_particle(x: float, y: float) -> CPUParticles2D:
	var particles = CPUParticles2D.new()
	particles.position = Vector2(x, y)
	particles.emitting = true
	particles.amount = 100
	particles.lifetime = 1.5
	particles.explosiveness = 0.0
	
	# Configure particle properties
	particles.direction = Vector2(0, -1)
	particles.initial_velocity_min = 30.0
	particles.initial_velocity_max = 60.0
	particles.gravity = Vector2(0, -20)  # Negative gravity makes particles go up
	particles.scale_min = 0.8
	particles.scale_max = 2.0
	
	# Flame colors (orange to red to yellow)
	particles.color = Color(1.0, 0.5, 0.0)  # Orange
	var color_ramp = Gradient.new()
	color_ramp.colors = PackedColorArray([
		Color(1.0, 0.5, 0.0, 1.0),  # Orange
		Color(1.0, 0.2, 0.0, 1.0),  # Red-orange
		Color(1.0, 0.8, 0.0, 0.5),  # Yellow-orange
		Color(0.3, 0.1, 0.0, 0.0)   # Dark red (fade out)
	])
	color_ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
	particles.color_ramp = color_ramp
	
	# Use texture for particles
	particles.texture = _create_flame_texture()
	
	print("[BurningBridge] Created flame particle at ", Vector2(x, y))
	
	return particles

func _create_flame_texture() -> Texture2D:
	# Create a simple flame-like texture programmatically
	var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))
	
	# Create a gradient from center (bright) to edges (transparent)
	for x in range(16):
		for y in range(16):
			var center = Vector2(8, 8)
			var dist = Vector2(x, y).distance_to(center)
			var alpha = 1.0 - (dist / 8.0)
			alpha = clamp(alpha, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	
	var texture = ImageTexture.create_from_image(image)
	return texture

func _setup_flames() -> void:
	# Create multiple flame particle systems along the bridge
	var viewport_size = get_viewport_rect().size
	if viewport_size.x == 0 or viewport_size.y == 0:
		# Viewport not ready yet, try again next frame
		call_deferred("_setup_flames")
		return
	
	var center_y = viewport_size.y * 0.7
	var bridge_width = viewport_size.x * 0.8
	var start_x = viewport_size.x * 0.1
	
	# Create 5 flame sources along the bridge
	for i in range(5):
		var flame_x = start_x + (bridge_width / 4.0) * i
		var flame_pos = Vector2(flame_x, center_y - 10)
		_flame_base_positions.append(flame_pos)
		var flame = _create_flame_particle(flame_x, center_y - 10)
		add_child(flame)
		_flame_particles.append(flame)

func _update_flames() -> void:
	# Animate flame intensity and position slightly
	for i in range(_flame_particles.size()):
		var flame = _flame_particles[i]
		if flame == null or i >= _flame_base_positions.size():
			continue
		# Slight horizontal sway
		var sway = sin(_time * 2.0 + i) * 3.0
		flame.position.x = _flame_base_positions[i].x + sway
		flame.position.y = _flame_base_positions[i].y
		
		# Vary emission rate for flickering effect
		var base_rate = 100.0
		var flicker = 0.7 + sin(_time * 5.0 + i * 2.0) * 0.3
		flame.amount = int(base_rate * flicker)

