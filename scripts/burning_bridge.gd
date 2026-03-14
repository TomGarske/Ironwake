extends CanvasLayer

# ---------------------------------------------------------------------------
# Burning Bridge Background Animation
# ---------------------------------------------------------------------------

var _flame_particles: Array[CPUParticles2D] = []
var _flame_base_positions: Array[Vector2] = []
var _bridge_points: Array[Vector2] = []
var _time: float = 0.0
var _bridge_drawer: Node2D
var _bridge_center_y: float = 0.0
var _bridge_width: float = 0.0
var _bridge_start_x: float = 0.0
var _flame_texture: Texture2D

func _ready() -> void:
	layer = -1  # Behind everything
	
	# Create a Node2D child for drawing
	_bridge_drawer = Node2D.new()
	_bridge_drawer.name = "BridgeDrawer"
	_bridge_drawer.set_script(preload("res://scripts/bridge_drawer.gd"))
	add_child(_bridge_drawer)
	_flame_texture = _create_flame_texture()
	
	# Wait for viewport to be ready
	call_deferred("_setup_bridge")
	call_deferred("_setup_flames")

func _process(delta: float) -> void:
	_time += delta
	if _bridge_drawer:
		_bridge_drawer.bridge_points = _bridge_points
		_bridge_drawer.time = _time
		_bridge_drawer.queue_redraw()
	_update_flames()

func _setup_bridge() -> void:
	# Create bridge structure points (simple arch/bridge shape)
	var viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x == 0 or viewport_size.y == 0:
		# Viewport not ready yet, try again next frame
		call_deferred("_setup_bridge")
		return
	
	var center_y = viewport_size.y * 0.7  # Position bridge in lower portion
	var bridge_width = viewport_size.x * 0.8
	var bridge_height = 80.0
	var start_x = viewport_size.x * 0.1
	var end_x = start_x + bridge_width

	_bridge_center_y = center_y
	_bridge_width = bridge_width
	_bridge_start_x = start_x
	
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
func _create_flame_particle(x: float, y: float, flame_texture: Texture2D) -> CPUParticles2D:
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
	particles.scale_amount_min = 0.8
	particles.scale_amount_max = 2.0
	
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
	particles.texture = flame_texture
	
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
	var viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x == 0 or viewport_size.y == 0:
		# Viewport not ready yet, try again next frame
		call_deferred("_setup_flames")
		return
	if _bridge_width <= 0.0:
		_setup_bridge()
		call_deferred("_setup_flames")
		return
	if _flame_texture == null:
		_flame_texture = _create_flame_texture()
	_flame_base_positions.clear()
	_flame_particles.clear()
	
	# Create 5 flame sources along the bridge
	for i in range(5):
		var flame_x = _bridge_start_x + (_bridge_width / 4.0) * i
		var flame_pos = Vector2(flame_x, _bridge_center_y - 10.0)
		_flame_base_positions.append(flame_pos)
		var flame = _create_flame_particle(flame_x, _bridge_center_y - 10.0, _flame_texture)
		_bridge_drawer.add_child(flame)
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
