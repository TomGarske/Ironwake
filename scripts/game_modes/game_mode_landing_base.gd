extends Control

const UiStyleScript := preload("res://scripts/ui/ui_style.gd")

@export var mode_title: String = "Mode Prototype"
@export var mode_subtitle: String = "Base Template"
@export_multiline var mode_description: String = "This mode is currently a prototype shell."

@onready var mode_card: PanelContainer = $ModeCard
@onready var title_label: Label = $ModeCard/VBoxContainer/TitleLabel
@onready var subtitle_label: Label = $ModeCard/VBoxContainer/SubtitleLabel
@onready var description_label: Label = $ModeCard/VBoxContainer/DescriptionLabel
@onready var back_button: Button = $ModeCard/VBoxContainer/BackButton

func _ready() -> void:
	UiStyleScript.style_panel(mode_card)
	title_label.text = mode_title
	subtitle_label.text = mode_subtitle
	description_label.text = mode_description
	UiStyleScript.style_title(title_label, 30)
	UiStyleScript.style_body(subtitle_label, true)
	subtitle_label.add_theme_font_size_override("font_size", 18)
	UiStyleScript.style_body(description_label)
	back_button.text = "Return to Command Hub"
	UiStyleScript.style_button(back_button)
	if not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)

func _on_back_button_pressed() -> void:
	if SteamManager != null and SteamManager.lobby_id != 0:
		SteamManager.leave_lobby()
	if GameManager != null:
		GameManager.reset()
	get_tree().change_scene_to_file(GameManager.HOME_SCREEN_SCENE_PATH)
