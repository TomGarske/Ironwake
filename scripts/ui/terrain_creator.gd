extends Control

## Terrain Creator UI — styled with UiStyle (project sci-fi palette).
## All terrain types are editable. Delete is greyed out when in use.
## Custom terrains persist to disk via GameState.

const UiStyleScript := preload("res://scripts/ui/ui_style.gd")

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var _terrain_vbox:   VBoxContainer     = $HSplitContainer/TerrainListPanel/TerrainScrollList/TerrainVBox
@onready var _label_input:    LineEdit          = $HSplitContainer/EditPanel/LabelInput
@onready var _color_picker:   ColorPickerButton = $HSplitContainer/EditPanel/ColorPicker
@onready var _land_toggle:    CheckButton       = $HSplitContainer/EditPanel/MovementToggles/LandToggle
@onready var _air_toggle:     CheckButton       = $HSplitContainer/EditPanel/MovementToggles/AirToggle
@onready var _water_toggle:   CheckButton       = $HSplitContainer/EditPanel/MovementToggles/WaterToggle
@onready var _deep_toggle:    CheckButton       = $HSplitContainer/EditPanel/MovementToggles/DeepToggle
@onready var _create_button:  Button            = $HSplitContainer/EditPanel/ButtonRow/CreateButton
@onready var _close_button:   Button            = $HSplitContainer/EditPanel/ButtonRow/CloseButton
@onready var _status_label:   Label             = $HSplitContainer/EditPanel/StatusLabel
@onready var _cell_label:     Label             = $HSplitContainer/EditPanel/CellSection/CellLabel
@onready var _cell_option:    OptionButton      = $HSplitContainer/EditPanel/CellSection/CellOption
@onready var _cell_apply_btn: Button            = $HSplitContainer/EditPanel/CellSection/CellButtonRow/CellApplyButton
@onready var _create_new_btn: Button            = $HSplitContainer/EditPanel/CellSection/CellButtonRow/CreateNewButton
@onready var _editor_title:   Label             = $HSplitContainer/EditPanel/EditorTitle
@onready var _list_title:     Label             = $HSplitContainer/TerrainListPanel/ListTitle

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _editing_id: String = ""
var _selected_cell: Vector2i = Vector2i(-1, -1)

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	_apply_ui_style()
	_rebuild_list()
	_create_button.pressed.connect(_on_create_pressed)
	_close_button.pressed.connect(_on_close_pressed)
	_cell_apply_btn.pressed.connect(_on_cell_apply_pressed)
	_create_new_btn.pressed.connect(_on_create_new_pressed)
	_color_picker.color_changed.connect(_on_color_changed)
	TerrainDefinitions.terrain_updated.connect(_rebuild_list)
	TerrainDefinitions.terrain_updated.connect(_refresh_cell_option)
	visibility_changed.connect(_rebuild_list)
	_cell_label.text = "No cell selected"
	_cell_option.disabled = true
	_cell_apply_btn.disabled = true

# ---------------------------------------------------------------------------
# Styling — project UiStyle palette
# ---------------------------------------------------------------------------

func _apply_ui_style() -> void:
	# Panel background
	add_theme_stylebox_override("panel", UiStyleScript.make_panel_style())

	# Inherited theme for all child controls
	var t := Theme.new()
	var btn := UiStyleScript.make_button_styles()
	for style_name: String in btn.keys():
		t.set_stylebox(style_name, "Button", btn[style_name])
	t.set_color("font_color",          "Button", UiStyleScript.TEXT_PRIMARY)
	t.set_color("font_hover_color",    "Button", UiStyleScript.TEXT_PRIMARY)
	t.set_color("font_pressed_color",  "Button", UiStyleScript.TEXT_PRIMARY)
	t.set_color("font_disabled_color", "Button", UiStyleScript.TEXT_MUTED)
	t.set_font_size("font_size",       "Button", 14)

	var inp := UiStyleScript.make_input_styles()
	t.set_stylebox("normal", "LineEdit", inp["normal"])
	t.set_stylebox("focus",  "LineEdit", inp["focus"])
	t.set_color("font_color",             "LineEdit", UiStyleScript.TEXT_PRIMARY)
	t.set_color("font_placeholder_color", "LineEdit", UiStyleScript.TEXT_SECONDARY)

	t.set_color("font_color", "Label",        UiStyleScript.TEXT_PRIMARY)
	t.set_color("font_color", "OptionButton", UiStyleScript.TEXT_PRIMARY)
	t.set_color("font_color", "CheckButton",  UiStyleScript.TEXT_PRIMARY)

	self.theme = t

	# Title labels slightly larger
	UiStyleScript.style_title(_list_title, 16)
	UiStyleScript.style_title(_editor_title, 16)

# ---------------------------------------------------------------------------
# Selected cell
# ---------------------------------------------------------------------------

func select_cell(cell: Vector2i) -> void:
	_selected_cell = cell
	var strategy := _get_strategy_game()
	if strategy and cell.x >= 0:
		var terrain: String = strategy.get_terrain_at(cell)
		_cell_label.text = "Cell (%d, %d)  —  %s" % [
			cell.x, cell.y, TerrainDefinitions.get_terrain_label(terrain)]
		_refresh_cell_option()
		var ids := TerrainDefinitions.get_all_terrain_ids()
		for i in ids.size():
			if ids[i] == terrain:
				_cell_option.select(i)
				break
		_cell_option.disabled = false
		_cell_apply_btn.disabled = false
	else:
		_cell_label.text = "No cell selected"
		_cell_option.disabled = true
		_cell_apply_btn.disabled = true

func _refresh_cell_option() -> void:
	var prev := _cell_option.selected
	_cell_option.clear()
	for id: String in TerrainDefinitions.get_all_terrain_ids():
		_cell_option.add_item(TerrainDefinitions.get_terrain_label(id))
	if prev >= 0 and prev < _cell_option.item_count:
		_cell_option.select(prev)

func _on_cell_apply_pressed() -> void:
	if _selected_cell.x < 0:
		return
	var ids := TerrainDefinitions.get_all_terrain_ids()
	var idx := _cell_option.selected
	if idx < 0 or idx >= ids.size():
		return
	var strategy := _get_strategy_game()
	if strategy:
		strategy.set_tile_terrain(_selected_cell, ids[idx])
		_cell_label.text = "Cell (%d, %d)  —  %s" % [
			_selected_cell.x, _selected_cell.y,
			TerrainDefinitions.get_terrain_label(ids[idx])]

func _on_create_new_pressed() -> void:
	_clear_form()
	_label_input.grab_focus()

# ---------------------------------------------------------------------------
# Terrain list
# ---------------------------------------------------------------------------

func _rebuild_list() -> void:
	for child in _terrain_vbox.get_children():
		child.queue_free()

	for id: String in TerrainDefinitions.get_all_terrain_ids():
		var in_use := _is_terrain_in_use(id)
		var captured_id := id

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.color = TerrainDefinitions.get_terrain_color(id)
		row.add_child(swatch)

		var lbl := Label.new()
		lbl.text = TerrainDefinitions.get_terrain_label(id)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", UiStyleScript.TEXT_PRIMARY)
		row.add_child(lbl)

		var edit_btn := Button.new()
		edit_btn.text = "Edit"
		UiStyleScript.style_button(edit_btn)
		edit_btn.pressed.connect(func() -> void: _on_edit_pressed(captured_id))
		row.add_child(edit_btn)

		var del_btn := Button.new()
		del_btn.text = "Del"
		del_btn.disabled = in_use
		if in_use:
			del_btn.tooltip_text = "In use on the map"
		UiStyleScript.style_button(del_btn)
		del_btn.pressed.connect(func() -> void: _on_delete_pressed(captured_id))
		row.add_child(del_btn)

		_terrain_vbox.add_child(row)

func _is_terrain_in_use(id: String) -> bool:
	var strategy := _get_strategy_game()
	if not strategy:
		return false
	for terrain: String in strategy.hex_terrain_map.values():
		if terrain == id:
			return true
	return false

# ---------------------------------------------------------------------------
# Create / Update
# ---------------------------------------------------------------------------

func _on_create_pressed() -> void:
	var label := _label_input.text.strip_edges()
	if label.is_empty():
		_set_status("Label cannot be empty.", true)
		return

	var movement: Array[String] = []
	if _land_toggle.button_pressed:  movement.append("land")
	if _air_toggle.button_pressed:   movement.append("air")
	if _water_toggle.button_pressed: movement.append("water")
	if _deep_toggle.button_pressed:  movement.append("deep_ocean_underwater")

	if not _editing_id.is_empty():
		TerrainDefinitions.update_terrain(_editing_id, {
			"id": _editing_id,
			"label": label,
			"color": _color_picker.color,
			"required_movement_types": movement,
		})
		_set_status("Updated '%s'." % label, false)
		_clear_form()
		_rebuild_list()
		return

	var raw_id := _label_to_id(label)
	var suffix := 2
	while not TerrainDefinitions.is_id_unique(raw_id):
		raw_id = _label_to_id(label) + "_%d" % suffix
		suffix += 1

	TerrainDefinitions.add_custom_terrain({
		"id": raw_id,
		"label": label,
		"color": _color_picker.color,
		"required_movement_types": movement,
	})
	_set_status("Created '%s'." % label, false)
	_clear_form()
	_rebuild_list()

# ---------------------------------------------------------------------------
# Edit / Delete
# ---------------------------------------------------------------------------

func _on_edit_pressed(id: String) -> void:
	_editing_id = id
	var is_builtin := TerrainDefinitions.is_builtin(id)

	if is_builtin:
		var data: Dictionary = TerrainDefinitions.TERRAIN_TYPES[id]
		_label_input.text      = data.get("label", id)
		_color_picker.color    = data.get("color", Color.WHITE)
		_color_picker.disabled = true
		var movement: Array    = data.get("required_movement_types", [])
		_land_toggle.button_pressed  = "land"                  in movement
		_air_toggle.button_pressed   = "air"                   in movement
		_water_toggle.button_pressed = "water"                 in movement
		_deep_toggle.button_pressed  = "deep_ocean_underwater" in movement
	else:
		var ct := _find_custom(id)
		_label_input.text      = ct.get("label", "")
		_color_picker.color    = ct.get("color", Color.WHITE)
		_color_picker.disabled = false
		var movement: Array    = ct.get("required_movement_types", [])
		_land_toggle.button_pressed  = "land"                  in movement
		_air_toggle.button_pressed   = "air"                   in movement
		_water_toggle.button_pressed = "water"                 in movement
		_deep_toggle.button_pressed  = "deep_ocean_underwater" in movement

	_create_button.text = "Update"
	_set_status("Editing '%s'." % TerrainDefinitions.get_terrain_label(id), false)

func _on_delete_pressed(id: String) -> void:
	if _is_terrain_in_use(id):
		return
	TerrainDefinitions.remove_terrain(id)
	if _editing_id == id:
		_clear_form()
	_rebuild_list()
	_set_status("Deleted.", false)

func _on_close_pressed() -> void:
	_clear_form()
	var strategy := _get_strategy_game()
	if strategy and strategy.has_method("clear_pinned_cell"):
		strategy.clear_pinned_cell()
	get_parent().visible = false

# ---------------------------------------------------------------------------
# Live color preview (custom terrains only)
# ---------------------------------------------------------------------------

func _on_color_changed(color: Color) -> void:
	if _editing_id.is_empty() or TerrainDefinitions.is_builtin(_editing_id):
		return
	var strategy := _get_strategy_game()
	if strategy and strategy.has_method("_update_custom_terrain_color"):
		strategy._update_custom_terrain_color(_editing_id, color)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _label_to_id(label: String) -> String:
	var result := ""
	for ch: String in label.strip_edges().to_lower().replace(" ", "_").replace("-", "_"):
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
			result += ch
	return result if not result.is_empty() else "custom"

func _find_custom(id: String) -> Dictionary:
	for ct: Dictionary in TerrainDefinitions.custom_terrains:
		if ct["id"] == id:
			return ct
	return {}

func _get_strategy_game() -> Node:
	var nodes := get_tree().get_nodes_in_group("strategy_game")
	return nodes[0] if nodes.size() > 0 else null

func _clear_form() -> void:
	_editing_id = ""
	_label_input.text      = ""
	_color_picker.color    = Color(0.5, 0.8, 0.3)
	_color_picker.disabled = false
	_land_toggle.button_pressed  = false
	_air_toggle.button_pressed   = false
	_water_toggle.button_pressed = false
	_deep_toggle.button_pressed  = false
	_create_button.text = "Create"

func _set_status(msg: String, is_error: bool) -> void:
	_status_label.text     = msg
	_status_label.modulate = UiStyleScript.DANGER if is_error else UiStyleScript.ACCENT_SOFT
