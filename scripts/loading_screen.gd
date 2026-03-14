extends Control

@onready var subtitle_label: Label = $Center/CardPanel/VBoxContainer/Subtitle
@onready var progress_bar: ProgressBar = $Center/CardPanel/VBoxContainer/ProgressBar
@onready var spinner: Label = $Center/CardPanel/VBoxContainer/Spinner
@onready var glow_top: ColorRect = $AmbientGlowTop

const _LOAD_DURATION: float = 2.2
const _SPINNER_FRAMES: Array[String] = ["|", "/", "-", "\\"]

var _elapsed: float = 0.0

func _ready() -> void:
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	_update_spinner()

func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(_elapsed / _LOAD_DURATION, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	progress_bar.value = eased * 100.0
	subtitle_label.text = "Forging bridges... %d%%" % int(progress_bar.value)
	_update_spinner()
	_update_glow()

	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
		_go_to_main_menu()
		return

	if t >= 1.0:
		_go_to_main_menu()

func _update_spinner() -> void:
	var frame_idx: int = int(floor(_elapsed * 8.0)) % _SPINNER_FRAMES.size()
	spinner.text = _SPINNER_FRAMES[frame_idx]
	var pulse: float = 0.75 + 0.25 * sin(_elapsed * 5.0)
	spinner.modulate = Color(0.90, 0.68, 0.34, pulse)

func _update_glow() -> void:
	var glow_pulse: float = 0.16 + 0.08 * sin(_elapsed * 1.8)
	glow_top.color = Color(0.52, 0.36, 0.18, glow_pulse)

func _go_to_main_menu() -> void:
	set_process(false)
	get_tree().change_scene_to_file(GameManager.MAIN_MENU_SCENE_PATH)
