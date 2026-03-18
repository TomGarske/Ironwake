extends VBoxContainer

## Creature builder UI — point-buy system for designing creatures.
## Styled with UiStyle (project sci-fi palette), matching terrain_creator.

signal creature_confirmed(creature_data: Dictionary)

const UiStyleScript := preload("res://scripts/ui/ui_style.gd")

var _points_remaining: int = PointCostConstants.TOTAL_STARTING_POINTS
var _creature_counter: int = 0

# Control refs (built dynamically)
var _name_input: LineEdit
var _size_buttons: Dictionary = {}    # size_name → Button
var _movement_checks: Dictionary = {} # movement_id → CheckButton
var _speed_spin: SpinBox
var _vision_spin: SpinBox
var _health_spin: SpinBox
var _attack_spin: SpinBox
var _defense_spin: SpinBox
var _points_label: Label
var _confirm_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build_ui()


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	# ── Section title ──────────────────────────────────────────────
	var title := Label.new()
	title.text = "New Creature"
	UiStyleScript.style_title(title, 15)
	add_child(title)
	add_child(_make_separator())

	# Name row
	var name_row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = "Name:"
	name_lbl.custom_minimum_size = Vector2(52, 0)
	UiStyleScript.style_body(name_lbl)
	name_row.add_child(name_lbl)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Creature name..."
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyleScript.style_line_edit(_name_input)
	_name_input.text_changed.connect(_update_points)
	name_row.add_child(_name_input)
	add_child(name_row)

	# Physical size
	var size_lbl := Label.new()
	size_lbl.text = "Physical Size"
	UiStyleScript.style_body(size_lbl)
	add_child(size_lbl)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 3)
	var btn_group := ButtonGroup.new()
	for size_name: String in PointCostConstants.PHYSICAL_SIZE_COSTS.keys():
		var btn := Button.new()
		btn.text = size_name
		btn.toggle_mode = true
		btn.button_group = btn_group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiStyleScript.style_button(btn)
		btn.toggled.connect(_update_points.unbind(1))
		size_row.add_child(btn)
		_size_buttons[size_name] = btn
	_size_buttons["Small"].button_pressed = true
	add_child(size_row)

	# Movement type
	var move_lbl := Label.new()
	move_lbl.text = "Movement Type"
	UiStyleScript.style_body(move_lbl)
	add_child(move_lbl)

	var move_row := HBoxContainer.new()
	move_row.add_theme_constant_override("separation", 3)
	var movement_options := {
		"land":                  "Land",
		"air":                   "Air",
		"water":                 "Water",
		"deep_ocean_underwater": "Deep Ocean",
	}
	for mt_id: String in movement_options.keys():
		var cb := CheckButton.new()
		cb.text = movement_options[mt_id]
		cb.add_theme_color_override("font_color", UiStyleScript.TEXT_PRIMARY)
		cb.toggled.connect(_update_points.unbind(1))
		move_row.add_child(cb)
		_movement_checks[mt_id] = cb
	add_child(move_row)

	# Stats grid
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	_speed_spin   = _make_stat_row(grid, "Speed",   1, 1, 10)
	_vision_spin  = _make_stat_row(grid, "Vision",  3, 1, 20)
	_health_spin  = _make_stat_row(grid, "Health",  0, 0, 20)
	_attack_spin  = _make_stat_row(grid, "Attack",  0, 0, 20)
	_defense_spin = _make_stat_row(grid, "Defense", 0, 0, 20)
	add_child(grid)

	# Points remaining
	var pts_row := HBoxContainer.new()
	var pts_hdr := Label.new()
	pts_hdr.text = "Points left:"
	pts_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyleScript.style_body(pts_hdr)
	pts_row.add_child(pts_hdr)
	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 15)
	pts_row.add_child(_points_label)
	add_child(pts_row)

	# Confirm button
	_confirm_button = Button.new()
	_confirm_button.text = "Confirm Creature"
	UiStyleScript.style_button(_confirm_button)
	_confirm_button.pressed.connect(_on_confirm)
	add_child(_confirm_button)

	_update_points("")


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", UiStyleScript.BORDER_SOFT)
	return sep


func _make_stat_row(grid: GridContainer, label_text: String,
		default_val: int, min_val: int, max_val: int) -> SpinBox:
	var lbl := Label.new()
	lbl.text = label_text + ":"
	UiStyleScript.style_body(lbl)
	grid.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = default_val
	spin.custom_minimum_size = Vector2(68, 0)
	spin.value_changed.connect(_update_points.unbind(1))
	grid.add_child(spin)
	return spin


func _get_selected_size() -> String:
	for size_name: String in _size_buttons.keys():
		if _size_buttons[size_name].button_pressed:
			return size_name
	return "Small"


func _get_selected_movement_types() -> Array[String]:
	var result: Array[String] = []
	for mt_id: String in _movement_checks.keys():
		if _movement_checks[mt_id].button_pressed:
			result.append(mt_id)
	return result


func _calculate_cost() -> int:
	if not _health_spin or not _attack_spin or not _defense_spin or not _vision_spin:
		return 0
	var cost := 0
	var phys_size := _get_selected_size()
	cost += PointCostConstants.PHYSICAL_SIZE_COSTS.get(phys_size, 0)
	var mts := _get_selected_movement_types()
	cost += mts.size() * PointCostConstants.MOVEMENT_TYPE_COST
	cost += int(_health_spin.value) * PointCostConstants.HEALTH_COST
	cost += int(_attack_spin.value) * PointCostConstants.ATTACK_COST
	cost += int(_defense_spin.value) * PointCostConstants.DEFENSE_COST
	var extra_vision: int = maxi(0, int(_vision_spin.value) - 3)
	cost += extra_vision * PointCostConstants.VISION_COST_PER_HEX
	return cost


func _update_points(_val: Variant = null) -> void:
	var spent := _calculate_cost()
	_points_remaining = PointCostConstants.TOTAL_STARTING_POINTS - spent
	if not _points_label:
		return
	_points_label.text = str(_points_remaining)
	if _points_remaining < 0:
		_points_label.add_theme_color_override("font_color", UiStyleScript.DANGER)
	else:
		_points_label.add_theme_color_override("font_color", UiStyleScript.ACCENT)

	var has_name := _name_input != null and _name_input.text.strip_edges().length() > 0
	if _confirm_button:
		_confirm_button.disabled = _points_remaining < 0 or not has_name


func _on_confirm() -> void:
	_creature_counter += 1
	var creature_id: String = "creature_%d" % _creature_counter
	if multiplayer.has_multiplayer_peer():
		creature_id = "p%d_%s" % [multiplayer.get_unique_id(), creature_id]
	var creature_data := {
		"id":             creature_id,
		"name":           _name_input.text.strip_edges(),
		"physical_size":  _get_selected_size(),
		"movement_types": _get_selected_movement_types(),
		"movement_speed": int(_speed_spin.value),
		"vision":         int(_vision_spin.value),
		"health":         int(_health_spin.value),
		"attack":         int(_attack_spin.value),
		"defense":        int(_defense_spin.value),
	}
	creature_confirmed.emit(creature_data)
	_name_input.text = ""
	_update_points("")
