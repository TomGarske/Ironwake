extends PanelContainer

## Attribute editor — view built-in attributes and create/edit/delete custom ones.

signal attributes_changed

var _tree: Tree
var _name_input: LineEdit
var _category_option: OptionButton
var _new_category_input: LineEdit
var _cost_spin: SpinBox
var _base_spin: SpinBox
var _desc_input: LineEdit
var _status_label: Label

const _BUILTIN_CATEGORIES := ["Movement", "Combat", "Special"]


func _ready() -> void:
	_build_ui()
	_refresh_tree()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	add_child(vbox)

	var title := Label.new()
	title.text = "Attribute Editor"
	vbox.add_child(title)

	_tree = Tree.new()
	_tree.custom_minimum_size = Vector2(300, 200)
	_tree.hide_root = false
	vbox.add_child(_tree)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var form_lbl := Label.new()
	form_lbl.text = "Add / Edit Attribute"
	vbox.add_child(form_lbl)

	var name_row := HBoxContainer.new()
	var nl := Label.new()
	nl.text = "Name:"
	name_row.add_child(nl)
	_name_input = LineEdit.new()
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_input)
	vbox.add_child(name_row)

	var cat_row := HBoxContainer.new()
	var cl := Label.new()
	cl.text = "Category:"
	cat_row.add_child(cl)
	_category_option = OptionButton.new()
	for cat in _BUILTIN_CATEGORIES:
		_category_option.add_item(cat)
	_category_option.add_item("New Category...")
	_category_option.item_selected.connect(_on_category_selected)
	cat_row.add_child(_category_option)
	vbox.add_child(cat_row)

	var new_cat_row := HBoxContainer.new()
	var ncl := Label.new()
	ncl.text = "New category name:"
	new_cat_row.add_child(ncl)
	_new_category_input = LineEdit.new()
	_new_category_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_cat_row.add_child(_new_category_input)
	new_cat_row.visible = false
	vbox.add_child(new_cat_row)
	_new_category_input.set_meta("row", new_cat_row)

	var cost_row := HBoxContainer.new()
	var costl := Label.new()
	costl.text = "Cost/pt:"
	cost_row.add_child(costl)
	_cost_spin = SpinBox.new()
	_cost_spin.min_value = 0
	_cost_spin.max_value = 10
	_cost_spin.value = 1
	cost_row.add_child(_cost_spin)
	vbox.add_child(cost_row)

	var base_row := HBoxContainer.new()
	var basel := Label.new()
	basel.text = "Base value:"
	base_row.add_child(basel)
	_base_spin = SpinBox.new()
	_base_spin.min_value = 0
	_base_spin.max_value = 100
	_base_spin.value = 0
	base_row.add_child(_base_spin)
	vbox.add_child(base_row)

	var desc_row := HBoxContainer.new()
	var dl := Label.new()
	dl.text = "Description:"
	desc_row.add_child(dl)
	_desc_input = LineEdit.new()
	_desc_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_row.add_child(_desc_input)
	vbox.add_child(desc_row)

	_status_label = Label.new()
	_status_label.text = ""
	vbox.add_child(_status_label)

	var btn_row := HBoxContainer.new()
	var create_btn := Button.new()
	create_btn.text = "Create / Update"
	create_btn.pressed.connect(_on_create_update)
	btn_row.add_child(create_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func() -> void: visible = false)
	btn_row.add_child(close_btn)
	vbox.add_child(btn_row)


func _on_category_selected(index: int) -> void:
	var opt_text: String = _category_option.get_item_text(index)
	var new_cat_row: Node = _new_category_input.get_meta("row")
	new_cat_row.visible = (opt_text == "New Category...")


func _refresh_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	root.set_text(0, "Attributes")

	# Group by category
	var by_cat: Dictionary = {}

	# Built-in attributes
	for attr: AttributeDefinition in AttributeDefinition.get_default_attributes():
		if not by_cat.has(attr.category):
			by_cat[attr.category] = []
		by_cat[attr.category].append({"attr": attr, "custom": false})

	# Custom attributes from GameState
	for ca: Dictionary in GameState.custom_attributes:
		var cat: String = ca.get("category", "Custom")
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append({"attr": ca, "custom": true})

	for cat: String in by_cat.keys():
		var cat_item := _tree.create_item(root)
		cat_item.set_text(0, cat)
		for entry: Dictionary in by_cat[cat]:
			var item := _tree.create_item(cat_item)
			if entry["custom"]:
				var ca: Dictionary = entry["attr"]
				item.set_text(0, "%s (cost %d, base %d)" % [
					ca.get("name", "?"),
					ca.get("cost_per_point", 1),
					ca.get("base_value", 0),
				])
			else:
				var attr: AttributeDefinition = entry["attr"]
				item.set_text(0, "%s (cost %d, base %d) [built-in]" % [
					attr.name, attr.cost_per_point, attr.base_value])


func _on_create_update() -> void:
	var attr_name := _name_input.text.strip_edges()
	if attr_name.is_empty():
		_status_label.text = "Name is required."
		return

	var cat_idx: int = _category_option.selected
	var category: String = _category_option.get_item_text(cat_idx)
	if category == "New Category...":
		category = _new_category_input.text.strip_edges()
		if category.is_empty():
			_status_label.text = "Category name is required."
			return
		# Add to option button if new
		var cat_exists := false
		for i in _category_option.item_count:
			if _category_option.get_item_text(i) == category:
				cat_exists = true
				break
		if not cat_exists:
			_category_option.add_item(category)
			# Move "New Category..." to end
			var last := _category_option.item_count - 1
			_category_option.remove_item(last - 1)
			_category_option.add_item("New Category...")

	var new_attr := {
		"name":          attr_name,
		"category":      category,
		"cost_per_point": int(_cost_spin.value),
		"base_value":    int(_base_spin.value),
		"description":   _desc_input.text,
		"is_custom":     true,
	}

	# Update or append
	var found := false
	for i in GameState.custom_attributes.size():
		if GameState.custom_attributes[i].get("name", "") == attr_name:
			GameState.custom_attributes[i] = new_attr
			found = true
			break
	if not found:
		GameState.custom_attributes.append(new_attr)

	_status_label.text = "Saved: %s" % attr_name
	_refresh_tree()
	attributes_changed.emit()

	# Clear form
	_name_input.text = ""
	_desc_input.text = ""
