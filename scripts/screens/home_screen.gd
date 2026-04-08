extends Control
const UiStyleScript := preload("res://scripts/ui/ui_style.gd")

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var join_input: LineEdit = $RightLobbyPanel/VBoxContainer/JoinLobbyIdInput
@onready var confirm_join_button: Button = $RightLobbyPanel/VBoxContainer/ConfirmJoinButton
@onready var host_button: Button = $LeftMenuPanel/VBoxContainer/HostButton
@onready var test_button: Button = $LeftMenuPanel/VBoxContainer/TestButton
@onready var settings_button: Button = $LeftMenuPanel/VBoxContainer/SettingsButton
@onready var exit_button: Button = $LeftMenuPanel/VBoxContainer/ExitButton
@onready var lobby_list_title: Label = $RightLobbyPanel/VBoxContainer/PublicLobbiesTitle
@onready var refresh_lobbies_button: Button = $RightLobbyPanel/VBoxContainer/RefreshLobbiesButton
@onready var lobby_list_status: Label = $RightLobbyPanel/VBoxContainer/LobbyListStatus
@onready var lobby_list: VBoxContainer = $RightLobbyPanel/VBoxContainer/LobbyListScroll/LobbyList
@onready var ship_class_selector: OptionButton = $LeftMenuPanel/VBoxContainer/ShipClassSelector
@onready var ship_class_desc: Label = $LeftMenuPanel/VBoxContainer/ShipClassDesc
@onready var version_label: Label = $VersionLabel
@onready var quit_confirm_dialog: ConfirmationDialog = $QuitConfirmDialog
@onready var settings_popup: PopupPanel = $SettingsPopup
@onready var sfx_volume_slider: HSlider = $SettingsPopup/SettingsMargin/VBoxContainer/SfxVolumeRow/SfxVolumeSlider
@onready var music_volume_row: HBoxContainer = $SettingsPopup/SettingsMargin/VBoxContainer/MusicVolumeRow
@onready var music_volume_slider: HSlider = $SettingsPopup/SettingsMargin/VBoxContainer/MusicVolumeRow/MusicVolumeSlider
@onready var music_intensity_row: HBoxContainer = $SettingsPopup/SettingsMargin/VBoxContainer/MusicIntensityRow
@onready var music_intensity_slider: HSlider = $SettingsPopup/SettingsMargin/VBoxContainer/MusicIntensityRow/MusicIntensitySlider
@onready var music_speed_row: HBoxContainer = $SettingsPopup/SettingsMargin/VBoxContainer/MusicSpeedRow
@onready var music_speed_slider: HSlider = $SettingsPopup/SettingsMargin/VBoxContainer/MusicSpeedRow/MusicSpeedSlider

var _menu_index: int = 0
var _menu_up_prev: bool = false
var _menu_down_prev: bool = false
var _menu_accept_prev: bool = false
var _menu_cancel_prev: bool = false
var _controller_debug_label: Label = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_update_version_label()
	_apply_warm_tactical_theme()
	_setup_menu_navigation()
	_setup_controller_debug_line()
	_setup_ship_class_selector()
	_sync_audio_settings_ui()
	_hide_music_settings_ui()
	_apply_dialog_theme()

	if SteamManager == null:
		push_error("[HomeScreen] SteamManager autoload missing.")
	else:
		SteamManager.lobby_created.connect(_on_lobby_ready)
		SteamManager.lobby_joined.connect(_on_lobby_ready)
		SteamManager.invite_join_requested.connect(_on_invite_join_requested)
		SteamManager.lobby_list_updated.connect(_on_lobby_list_updated)
		host_button.disabled = not SteamManager.steam_ready
		if host_button.disabled:
			host_button.tooltip_text = "Steam is not initialized. Check debug console output."
		# If app was launched from a Steam invite and joined before menu connected, continue to lobby.
		if SteamManager.lobby_id > 0:
			DebugOverlay.log_message("[HomeScreen] Existing lobby detected (%d). Entering lobby..." % SteamManager.lobby_id)
			call_deferred("_on_lobby_ready", SteamManager.lobby_id)

	refresh_lobbies_button.pressed.connect(_on_refresh_lobbies_pressed)
	if not quit_confirm_dialog.confirmed.is_connected(_on_quit_confirmed):
		quit_confirm_dialog.confirmed.connect(_on_quit_confirmed)
	if GameManager != null and not GameManager.audio_volume_changed.is_connected(_on_audio_volume_changed):
		GameManager.audio_volume_changed.connect(_on_audio_volume_changed)
	if music_volume_slider != null and not music_volume_slider.value_changed.is_connected(_on_music_volume_slider_changed):
		music_volume_slider.value_changed.connect(_on_music_volume_slider_changed)
	if music_intensity_slider != null and not music_intensity_slider.value_changed.is_connected(_on_music_intensity_slider_changed):
		music_intensity_slider.value_changed.connect(_on_music_intensity_slider_changed)
	if music_speed_slider != null and not music_speed_slider.value_changed.is_connected(_on_music_speed_slider_changed):
		music_speed_slider.value_changed.connect(_on_music_speed_slider_changed)
	_refresh_menu_selection()

	# Ensure menu music is playing (e.g. when returning from arena)
	if MusicPlayer != null:
		MusicPlayer.play_song(MusicPlayer.DEFAULT_MENU_SONG)

	DebugOverlay.log_message("[HomeScreen] Ready.")
	if SteamManager != null:
		_refresh_lobby_browser()

func _process(_delta: float) -> void:
	_handle_simple_controller_menu_input()
	_update_controller_debug_line()

func _apply_warm_tactical_theme() -> void:
	UiStyleScript.style_button(host_button)
	UiStyleScript.style_button(test_button)
	UiStyleScript.style_button(settings_button)
	UiStyleScript.style_button(exit_button)
	UiStyleScript.style_button(confirm_join_button)
	UiStyleScript.style_button(refresh_lobbies_button)
	ship_class_selector.add_theme_color_override("font_color", UiStyleScript.TEXT_PRIMARY)
	UiStyleScript.style_line_edit(join_input)
	var slider_rows := [
		$SettingsPopup/SettingsMargin/VBoxContainer/SfxVolumeRow/Label
	]
	for row_label in slider_rows:
		row_label.add_theme_color_override("font_color", UiStyleScript.TEXT_PRIMARY)

func _apply_dialog_theme() -> void:
	if quit_confirm_dialog == null:
		return
	quit_confirm_dialog.add_theme_stylebox_override("panel", UiStyleScript.make_panel_style())
	quit_confirm_dialog.add_theme_color_override("title_color", UiStyleScript.TEXT_PRIMARY)
	quit_confirm_dialog.add_theme_color_override("font_color", UiStyleScript.TEXT_SECONDARY)
	UiStyleScript.style_button(quit_confirm_dialog.get_ok_button())
	UiStyleScript.style_button(quit_confirm_dialog.get_cancel_button())

func _update_version_label() -> void:
	if version_label == null:
		return
	var base_version: String = str(ProjectSettings.get_setting("application/config/version", "dev"))
	var commit_hash: String = _get_runtime_commit_hash()
	version_label.text = "%s (%s)" % [base_version, commit_hash] if not commit_hash.is_empty() else base_version

func _get_runtime_commit_hash() -> String:
	# Runtime lookup avoids repo-writing version churn from CI commits.
	var output: Array = []
	var exit_code: int = OS.execute("git", PackedStringArray(["rev-parse", "--short", "HEAD"]), output, true)
	if exit_code != 0 or output.is_empty():
		return ""
	return str(output[0]).strip_edges()

func _setup_menu_navigation() -> void:
	host_button.focus_mode = Control.FOCUS_ALL
	test_button.focus_mode = Control.FOCUS_ALL
	settings_button.focus_mode = Control.FOCUS_ALL
	exit_button.focus_mode = Control.FOCUS_ALL
	confirm_join_button.focus_mode = Control.FOCUS_ALL
	refresh_lobbies_button.focus_mode = Control.FOCUS_ALL
	join_input.focus_mode = Control.FOCUS_ALL
	sfx_volume_slider.focus_mode = Control.FOCUS_ALL
	host_button.focus_neighbor_bottom = host_button.get_path_to(test_button)
	test_button.focus_neighbor_top = test_button.get_path_to(host_button)
	test_button.focus_neighbor_bottom = test_button.get_path_to(settings_button)
	settings_button.focus_neighbor_top = settings_button.get_path_to(test_button)
	settings_button.focus_neighbor_bottom = settings_button.get_path_to(exit_button)
	exit_button.focus_neighbor_top = exit_button.get_path_to(settings_button)
	exit_button.focus_neighbor_bottom = exit_button.get_path_to(host_button)
	_refresh_menu_selection()

func _get_enabled_menu_buttons() -> Array[Button]:
	var ordered: Array[Button] = [host_button, test_button, settings_button, exit_button]
	var enabled: Array[Button] = []
	for button in ordered:
		if button != null and button.visible and not button.disabled:
			enabled.append(button)
	return enabled

func _cycle_menu_focus(direction: int) -> void:
	var buttons: Array[Button] = _get_enabled_menu_buttons()
	if buttons.is_empty():
		return
	_menu_index = posmod(_menu_index + direction, buttons.size())
	buttons[_menu_index].grab_focus()

func _activate_selected_menu_button() -> void:
	var buttons: Array[Button] = _get_enabled_menu_buttons()
	if buttons.is_empty():
		return
	_menu_index = clampi(_menu_index, 0, buttons.size() - 1)
	buttons[_menu_index].pressed.emit()

func _handle_simple_controller_menu_input() -> void:
	var pad_id: int = _get_primary_pad_id()
	if pad_id < 0:
		_menu_up_prev = false
		_menu_down_prev = false
		_menu_accept_prev = false
		_menu_cancel_prev = false
		return

	var stick_y: float = Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_Y)
	var down_now: bool = _is_pad_pressed_any(pad_id, [JOY_BUTTON_DPAD_DOWN]) or stick_y > 0.60
	var up_now: bool = _is_pad_pressed_any(pad_id, [JOY_BUTTON_DPAD_UP]) or stick_y < -0.60
	if down_now and not _menu_down_prev:
		_cycle_menu_focus(1)
	if up_now and not _menu_up_prev:
		_cycle_menu_focus(-1)
	_menu_down_prev = down_now
	_menu_up_prev = up_now

	var accept_down: bool = _is_pad_pressed_any(pad_id, [
		JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_START
	])
	if accept_down and not _menu_accept_prev:
		_activate_selected_menu_button()
	_menu_accept_prev = accept_down

	var cancel_down: bool = _is_pad_pressed_any(pad_id, [
		JOY_BUTTON_B, JOY_BUTTON_Y, JOY_BUTTON_BACK
	])
	if cancel_down and not _menu_cancel_prev:
		_on_exit_button_pressed()
	_menu_cancel_prev = cancel_down

func _is_pad_pressed_any(pad_id: int, buttons: Array[int]) -> bool:
	for button in buttons:
		if Input.is_joy_button_pressed(pad_id, button):
			return true
	return false

func _refresh_menu_selection() -> void:
	var buttons: Array[Button] = _get_enabled_menu_buttons()
	if buttons.is_empty():
		return
	_menu_index = clampi(_menu_index, 0, buttons.size() - 1)
	buttons[_menu_index].grab_focus()

func _get_primary_pad_id() -> int:
	var pads: PackedInt32Array = Input.get_connected_joypads()
	if pads.is_empty():
		return -1
	return int(pads[0])

func _setup_controller_debug_line() -> void:
	_controller_debug_label = Label.new()
	_controller_debug_label.name = "ControllerDebugLine"
	@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
	_controller_debug_label.layout_mode = 1 # LayoutMode.LAYOUT_MODE_ANCHORS
	_controller_debug_label.anchors_preset = 0
	_controller_debug_label.offset_left = 12.0
	_controller_debug_label.offset_top = 12.0
	_controller_debug_label.offset_right = 900.0
	_controller_debug_label.offset_bottom = 34.0
	_controller_debug_label.add_theme_font_size_override("font_size", 12)
	_controller_debug_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 0.95))
	_controller_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controller_debug_label.visible = false
	_controller_debug_label.text = "Controller debug initializing..."
	add_child(_controller_debug_label)

func _update_controller_debug_line() -> void:
	if _controller_debug_label == null:
		return
	var pad_ids: PackedInt32Array = Input.get_connected_joypads()
	var id_text: String = "none"
	if not pad_ids.is_empty():
		var parts: Array[String] = []
		for id in pad_ids:
			parts.append(str(id))
		id_text = ",".join(parts)

	var pad_id: int = _get_primary_pad_id()
	if pad_id < 0:
		_controller_debug_label.text = "Pads: [%s] | no active pad" % id_text
		return

	var a: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_A) else 0
	var b: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_B) else 0
	var x: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_X) else 0
	var y: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_Y) else 0
	var up: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_UP) else 0
	var down: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_DOWN) else 0
	var left: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_LEFT) else 0
	var right: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_DPAD_RIGHT) else 0
	var start: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_START) else 0
	var back: int = 1 if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_BACK) else 0
	var lx: float = Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_X)
	var ly: float = Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_Y)
	var ui_up: int = 1 if Input.is_action_pressed("ui_up") else 0
	var ui_down: int = 1 if Input.is_action_pressed("ui_down") else 0
	var ui_accept: int = 1 if Input.is_action_pressed("ui_accept") else 0
	var ui_cancel: int = 1 if Input.is_action_pressed("ui_cancel") else 0

	_controller_debug_label.text = "Pads:[%s] Active:%d | A:%d B:%d X:%d Y:%d U:%d D:%d L:%d R:%d Start:%d Back:%d | LX:%.2f LY:%.2f | ui U:%d D:%d A:%d C:%d" % [
		id_text, pad_id, a, b, x, y, up, down, left, right, start, back, lx, ly, ui_up, ui_down, ui_accept, ui_cancel
	]

func _exit_tree() -> void:
	if SteamManager != null:
		if SteamManager.lobby_created.is_connected(_on_lobby_ready):
			SteamManager.lobby_created.disconnect(_on_lobby_ready)
		if SteamManager.lobby_joined.is_connected(_on_lobby_ready):
			SteamManager.lobby_joined.disconnect(_on_lobby_ready)
		if SteamManager.invite_join_requested.is_connected(_on_invite_join_requested):
			SteamManager.invite_join_requested.disconnect(_on_invite_join_requested)
		if SteamManager.lobby_list_updated.is_connected(_on_lobby_list_updated):
			SteamManager.lobby_list_updated.disconnect(_on_lobby_list_updated)
	if GameManager != null and GameManager.audio_volume_changed.is_connected(_on_audio_volume_changed):
		GameManager.audio_volume_changed.disconnect(_on_audio_volume_changed)

# ---------------------------------------------------------------------------
# Ship class selector
# ---------------------------------------------------------------------------
func _setup_ship_class_selector() -> void:
	ship_class_selector.clear()
	for i in range(ShipClassConfig.CLASS_COUNT):
		ship_class_selector.add_item(ShipClassConfig.CLASS_NAMES[i])
	ship_class_selector.select(GameManager.local_ship_class)
	_update_ship_class_desc(GameManager.local_ship_class)
	if not ship_class_selector.item_selected.is_connected(_on_ship_class_selected):
		ship_class_selector.item_selected.connect(_on_ship_class_selected)

func _on_ship_class_selected(index: int) -> void:
	GameManager.set_local_ship_class(index)
	_update_ship_class_desc(index)

func _update_ship_class_desc(index: int) -> void:
	if ship_class_desc != null and index >= 0 and index < ShipClassConfig.CLASS_DESCRIPTIONS.size():
		ship_class_desc.text = ShipClassConfig.CLASS_DESCRIPTIONS[index]

# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------
func _on_host_button_pressed() -> void:
	DebugOverlay.log_message("[HomeScreen] Host button pressed.")
	if SteamManager != null:
		SteamManager.host_lobby()

func _on_confirm_join_button_pressed() -> void:
	var lobby_id: int = int(join_input.text.strip_edges())
	if lobby_id > 0:
		DebugOverlay.log_message("[HomeScreen] Attempting join for lobby %d." % lobby_id)
		if SteamManager != null:
			SteamManager.join_lobby(lobby_id)
	else:
		DebugOverlay.log_message("[HomeScreen] Invalid lobby ID entered.", true)

func _on_test_button_pressed() -> void:
	GameManager.start_offline_test_match("fleet_battle")

func _on_exit_button_pressed() -> void:
	quit_confirm_dialog.title = "Exit Ironwake"
	quit_confirm_dialog.ok_button_text = "Exit Game"
	quit_confirm_dialog.dialog_text = "Are you sure you want to close Ironwake and return to desktop?"
	quit_confirm_dialog.popup_centered()

func _on_settings_button_pressed() -> void:
	_sync_audio_settings_ui()
	settings_popup.popup_centered()

func _on_sfx_volume_slider_changed(value: float) -> void:
	if GameManager != null:
		GameManager.set_audio_volumes(GameManager.music_volume, value)

func _on_music_volume_slider_changed(value: float) -> void:
	if GameManager != null:
		GameManager.set_audio_volumes(value, GameManager.sfx_volume)

func _on_music_intensity_slider_changed(value: float) -> void:
	if GameManager != null:
		GameManager.set_music_profile(value, GameManager.music_speed, GameManager.music_tone)

func _on_music_speed_slider_changed(value: float) -> void:
	if GameManager != null:
		GameManager.set_music_profile(GameManager.music_intensity, value, GameManager.music_tone)

func _on_audio_volume_changed(_music_volume: float, _sfx_volume: float) -> void:
	_sync_audio_settings_ui()

func _sync_audio_settings_ui() -> void:
	if GameManager == null:
		return
	sfx_volume_slider.set_value_no_signal(GameManager.sfx_volume)
	if music_volume_slider != null:
		music_volume_slider.set_value_no_signal(GameManager.music_volume)
	if music_intensity_slider != null:
		music_intensity_slider.set_value_no_signal(GameManager.music_intensity)
	if music_speed_slider != null:
		music_speed_slider.set_value_no_signal(GameManager.music_speed)

func _hide_music_settings_ui() -> void:
	# Music system is active — show intensity and speed sliders.
	if music_intensity_row != null:
		music_intensity_row.visible = true
	if music_speed_row != null:
		music_speed_row.visible = true

func _on_quit_confirmed() -> void:
	get_tree().quit()

# ---------------------------------------------------------------------------
# Lobby ready callback
# ---------------------------------------------------------------------------
func _on_lobby_ready(_lobby_id: int) -> void:
	call_deferred("_do_scene_change_lobby")

func _do_scene_change_lobby() -> void:
	get_tree().change_scene_to_file(GameManager.LOBBY_SCENE_PATH)

func _on_invite_join_requested(target_lobby_id: int) -> void:
	DebugOverlay.log_message("[HomeScreen] Processing invite join request for lobby %d." % target_lobby_id)

func _on_refresh_lobbies_pressed() -> void:
	_refresh_lobby_browser()

func _refresh_lobby_browser() -> void:
	var can_query: bool = SteamManager != null and SteamManager.steam_ready
	lobby_list_title.visible = true
	refresh_lobbies_button.visible = true
	lobby_list_status.visible = true
	lobby_list.get_parent().visible = true
	if not can_query:
		lobby_list_status.text = "Steam not initialized yet."
		_rebuild_lobby_list([])
		return
	lobby_list_status.text = "Scanning for Ironwake operations..."
	SteamManager.request_burnbridgers_lobby_list()
	_rebuild_lobby_list(SteamManager.get_cached_public_lobbies())

func _on_join_lobby_from_list(target_lobby_id: int) -> void:
	DebugOverlay.log_message("[HomeScreen] Joining listed lobby %d." % target_lobby_id)
	join_input.text = str(target_lobby_id)
	if SteamManager != null:
		SteamManager.join_lobby(target_lobby_id)

func _on_lobby_list_updated(lobbies: Array) -> void:
	_rebuild_lobby_list(lobbies)
	if lobbies.is_empty():
		lobby_list_status.text = "No public Ironwake operations found."
	else:
		lobby_list_status.text = "%d Ironwake operation(s) found." % lobbies.size()

func _rebuild_lobby_list(lobbies: Array) -> void:
	for child in lobby_list.get_children():
		child.queue_free()
	if lobbies.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No operations yet. Open one to begin."
		UiStyleScript.style_body(empty_label, true)
		lobby_list.add_child(empty_label)
		return
	for item in lobbies:
		var lobby_id: int = int(item.get("lobby_id", 0))
		if lobby_id <= 0:
			continue
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lobby_name: String = str(item.get("name", "Ironwake Operation"))
		var members: int = int(item.get("members", 0))
		name_label.text = "%s (%d/%d)" % [lobby_name, members, GameConstants.MAX_PLAYERS]
		UiStyleScript.style_body(name_label)
		row.add_child(name_label)

		var join_button := Button.new()
		join_button.text = "Join"
		UiStyleScript.style_button(join_button)
		join_button.pressed.connect(_on_join_lobby_from_list.bind(lobby_id))
		row.add_child(join_button)

		lobby_list.add_child(row)
