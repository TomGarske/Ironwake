extends Node
const UiStyleScript := preload("res://scripts/ui/ui_style.gd")

const MAX_LINES: int = 300
const _EXPANDED_HEIGHT: float = 208.0
const _COLLAPSED_HEIGHT: float = 36.0

var _canvas: CanvasLayer
var _panel: PanelContainer
var _log: RichTextLabel
var _log_container: MarginContainer
var _collapse_button: Button
var _root: VBoxContainer
var _connected_to_steam: bool = false
var _collapsed: bool = true

func _ready() -> void:
	_build_ui()
	call_deferred("_try_connect_steam")

func _process(_delta: float) -> void:
	if not _connected_to_steam:
		_try_connect_steam()
	_sync_version_label_visibility()

func _input(event: InputEvent) -> void:
	if _panel == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_panel.visible = not _panel.visible
		_sync_version_label_visibility()

func log_message(message: String, is_error: bool = false) -> void:
	if _log == null:
		return
	var prefix: String = "[ERR] " if is_error else "[LOG] "
	_log.append_text(prefix + message + "\n")
	var all_text: String = _log.text
	var split_lines: PackedStringArray = all_text.split("\n", false)
	var lines: int = split_lines.size()
	if lines > MAX_LINES:
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
	_panel.offset_top = -_EXPANDED_HEIGHT - 12
	_panel.offset_right = -12
	_panel.offset_bottom = -12
	# Hidden by default; toggle with F3 when you want diagnostics.
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UiStyleScript.make_panel_style())
	_canvas.add_child(_panel)

	var root := VBoxContainer.new()
	_panel.add_child(root)
	_root = root

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "Debug Console (F3 to show/hide)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", UiStyleScript.TEXT_PRIMARY)
	header.add_child(title)

	_collapse_button = Button.new()
	_collapse_button.text = "-"
	_collapse_button.custom_minimum_size = Vector2(28, 24)
	UiStyleScript.style_button(_collapse_button)
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
	_log.add_theme_color_override("default_color", UiStyleScript.TEXT_SECONDARY)
	margin.add_child(_log)

	log_message("[DebugOverlay] Enabled (toggle with F3).")
	
	# Apply collapsed state by default
	_apply_collapsed_state()
	_sync_version_label_visibility()

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
	_apply_collapsed_state()

func _apply_collapsed_state() -> void:
	_log_container.visible = not _collapsed
	_collapse_button.text = "+" if _collapsed else "-"
	# Resize the panel itself so the background collapses too.
	var target_height: float = _COLLAPSED_HEIGHT if _collapsed else _EXPANDED_HEIGHT
	_panel.offset_top = -(target_height + 12.0)
	_root.queue_sort()

func _sync_version_label_visibility() -> void:
	if _panel == null:
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var version_node: Node = scene_root.get_node_or_null("VersionLabel")
	if version_node is CanvasItem:
		(version_node as CanvasItem).visible = _panel.visible
