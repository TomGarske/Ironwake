extends Node

const MAX_LINES: int = 300

var _canvas: CanvasLayer
var _panel: PanelContainer
var _log: RichTextLabel
var _log_container: MarginContainer
var _collapse_button: Button
var _connected_to_steam: bool = false
var _collapsed: bool = false

func _ready() -> void:
	if not OS.is_debug_build():
		return
	_build_ui()
	call_deferred("_try_connect_steam")

func _process(_delta: float) -> void:
	if not OS.is_debug_build():
		return
	if not _connected_to_steam:
		_try_connect_steam()

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_panel.visible = not _panel.visible

func log_message(message: String, is_error: bool = false) -> void:
	if not OS.is_debug_build():
		return
	var prefix: String = "[ERR] " if is_error else "[LOG] "
	_log.append_text(prefix + message + "\n")
	var lines: int = _log.get_line_count()
	if lines > MAX_LINES:
		var all_text: String = _log.text
		var split_lines: PackedStringArray = all_text.split("\n")
		var keep_from: int = maxi(0, split_lines.size() - MAX_LINES)
		_log.text = "\n".join(split_lines.slice(keep_from))
	_log.scroll_to_line(_log.get_line_count())

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 100
	add_child(_canvas)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 12
	_panel.offset_top = -220
	_panel.offset_right = -12
	_panel.offset_bottom = -12
	_canvas.add_child(_panel)

	var root := VBoxContainer.new()
	_panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "Debug Console (F3 to show/hide)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_collapse_button = Button.new()
	_collapse_button.text = "-"
	_collapse_button.custom_minimum_size = Vector2(28, 24)
	_collapse_button.pressed.connect(_on_toggle_collapsed)
	header.add_child(_collapse_button)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	root.add_child(margin)
	_log_container = margin

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 180)
	_log.bbcode_enabled = false
	_log.fit_content = false
	_log.scroll_active = true
	margin.add_child(_log)

	log_message("[DebugOverlay] Enabled (toggle with F3).")

func _try_connect_steam() -> void:
	if not has_node("/root/SteamManager"):
		return
	if _connected_to_steam:
		return
	var steam := get_node("/root/SteamManager")
	if steam == null:
		return
	steam.debug_message.connect(_on_steam_debug_message)
	_connected_to_steam = true
	log_message("[DebugOverlay] Connected to SteamManager log stream.")
	# Replay startup logs so early init errors are visible after scene load.
	for entry in steam.debug_history:
		log_message(str(entry.get("message", "")), bool(entry.get("is_error", false)))

func _on_steam_debug_message(message: String, is_error: bool) -> void:
	log_message(message, is_error)

func _on_toggle_collapsed() -> void:
	_collapsed = not _collapsed
	_log_container.visible = not _collapsed
	_collapse_button.text = "+" if _collapsed else "-"
