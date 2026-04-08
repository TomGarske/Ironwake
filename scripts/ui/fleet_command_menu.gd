## Radial fleet command menu: hold G to open, release on a sector to issue order.
## Quick-tap G still cycles orders sequentially (handled by arena, not here).
class_name FleetCommandMenu
extends RefCounted

const _WingmanController := preload("res://scripts/shared/wingman_controller.gd")

## Radial menu state.
var is_open: bool = false
## Center of the radial menu (screen coords, set when opened).
var center: Vector2 = Vector2.ZERO
## Currently hovered sector index (-1 = none).
var hovered_sector: int = -1
## Time the key has been held (used to distinguish tap vs hold).
var hold_time: float = 0.0
## Minimum hold duration to open the radial (seconds).
const HOLD_THRESHOLD: float = 0.20
## Radial menu radius (pixels).
const INNER_RADIUS: float = 30.0
const OUTER_RADIUS: float = 90.0

## Sector definitions: order index, label, icon symbol, color.
const SECTORS: Array[Dictionary] = [
	{"order": 0, "label": "Form Up", "icon": "V", "angle_start": -0.75, "color": Color(0.3, 0.7, 1.0, 0.9)},      # top
	{"order": 1, "label": "Attack", "icon": "X", "angle_start": -0.25, "color": Color(0.95, 0.35, 0.25, 0.9)},     # right
	{"order": 2, "label": "Hold", "icon": "O", "angle_start": 0.25, "color": Color(0.85, 0.75, 0.25, 0.9)},        # bottom
	{"order": 3, "label": "Break", "icon": "!", "angle_start": 0.75, "color": Color(0.6, 0.4, 0.9, 0.9)},           # left
]
const SECTOR_COUNT: int = 4


## Call each frame while the fleet order key is held.
## Returns: -1 if menu not ready, or the selected order index on release.
func process_input(delta: float, key_pressed: bool, key_just_pressed: bool,
		key_just_released: bool, mouse_pos: Vector2, vp_center: Vector2) -> int:
	if key_just_pressed:
		hold_time = 0.0
		center = vp_center
		hovered_sector = -1

	if key_pressed:
		hold_time += delta
		if hold_time >= HOLD_THRESHOLD:
			is_open = true
			# Determine hovered sector from mouse position.
			var rel: Vector2 = mouse_pos - center
			if rel.length() > INNER_RADIUS:
				# Angle in turns (0 = right, 0.25 = down, 0.5 = left, 0.75 = up).
				var angle_turns: float = fmod(rel.angle() / TAU + 1.0, 1.0)
				# Map to sector: each sector is 0.25 turns wide.
				# Sectors: 0=top (centered at 0.75 / -0.25), 1=right (0.0), 2=bottom (0.25), 3=left (0.5)
				# Offset so sector 0 (top) is centered at angle 0.75 (= -PI/2):
				var shifted: float = fmod(angle_turns + 0.125, 1.0)  # shift by half-sector
				hovered_sector = int(shifted * 4.0) % SECTOR_COUNT
				# Remap: 0=right, 1=bottom, 2=left, 3=top → we want 0=top, 1=right, 2=bottom, 3=left
				hovered_sector = (hovered_sector + 3) % SECTOR_COUNT
			else:
				hovered_sector = -1

	if key_just_released:
		var result: int = -1
		if is_open and hovered_sector >= 0:
			result = hovered_sector
		is_open = false
		hold_time = 0.0
		hovered_sector = -1
		return result

	return -1


## Draw the radial menu overlay.
func draw_menu(canvas: CanvasItem, current_order: int) -> void:
	if not is_open:
		return

	# Dim background.
	canvas.draw_circle(center, OUTER_RADIUS + 20.0, Color(0.0, 0.0, 0.0, 0.35))

	var font: Font = ThemeDB.fallback_font

	for i in range(SECTOR_COUNT):
		var sector: Dictionary = SECTORS[i]
		var angle_center: float = float(sector["angle_start"]) * TAU + TAU * 0.125
		var dir: Vector2 = Vector2.from_angle(angle_center)
		var sector_center: Vector2 = center + dir * (INNER_RADIUS + OUTER_RADIUS) * 0.5
		var is_hovered: bool = (i == hovered_sector)
		var is_current: bool = (i == current_order)

		# Sector background arc (simplified as filled circle segment).
		var bg_col: Color
		if is_hovered:
			bg_col = Color(sector["color"].r, sector["color"].g, sector["color"].b, 0.45)
		elif is_current:
			bg_col = Color(sector["color"].r, sector["color"].g, sector["color"].b, 0.20)
		else:
			bg_col = Color(0.15, 0.18, 0.25, 0.65)

		# Draw sector as a pie slice approximation (filled polygon).
		var arc_points: PackedVector2Array = PackedVector2Array()
		arc_points.append(center + Vector2.from_angle(float(sector["angle_start"]) * TAU) * INNER_RADIUS)
		var arc_steps: int = 8
		for s in range(arc_steps + 1):
			var t: float = float(s) / float(arc_steps)
			var a: float = (float(sector["angle_start"]) + t * 0.25) * TAU
			arc_points.append(center + Vector2.from_angle(a) * OUTER_RADIUS)
		arc_points.append(center + Vector2.from_angle((float(sector["angle_start"]) + 0.25) * TAU) * INNER_RADIUS)
		if arc_points.size() >= 3:
			canvas.draw_colored_polygon(arc_points, bg_col)

		# Sector border.
		var border_col: Color = sector["color"] if is_hovered else Color(0.5, 0.55, 0.65, 0.6)
		var start_angle: float = float(sector["angle_start"]) * TAU
		var end_angle: float = (float(sector["angle_start"]) + 0.25) * TAU
		canvas.draw_line(center + Vector2.from_angle(start_angle) * INNER_RADIUS,
			center + Vector2.from_angle(start_angle) * OUTER_RADIUS, border_col, 1.0)
		canvas.draw_line(center + Vector2.from_angle(end_angle) * INNER_RADIUS,
			center + Vector2.from_angle(end_angle) * OUTER_RADIUS, border_col, 1.0)

		# Label.
		var label_pos: Vector2 = center + dir * (OUTER_RADIUS + 14.0)
		var label_col: Color = sector["color"] if is_hovered else Color(0.75, 0.78, 0.85, 0.9)
		var label_size: int = 13 if is_hovered else 11
		canvas.draw_string(font, label_pos - Vector2(20.0, -4.0), sector["label"],
			HORIZONTAL_ALIGNMENT_CENTER, 50, label_size, label_col)

		# Current order marker.
		if is_current and not is_hovered:
			canvas.draw_circle(sector_center, 3.0, Color(1.0, 0.9, 0.3, 0.8))

	# Center dot.
	canvas.draw_circle(center, 4.0, Color(0.8, 0.85, 0.95, 0.9))
	canvas.draw_string(font, center - Vector2(8.0, -3.0), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(0.6, 0.65, 0.75, 0.8))
