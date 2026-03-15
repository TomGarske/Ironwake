extends RefCounted
class_name UiStyle

# Sci-fi tactical palette
const BG_DEEP: Color = Color(0.03, 0.04, 0.08, 1.0)
const BG_SURFACE: Color = Color(0.08, 0.11, 0.18, 0.95)
const BG_SURFACE_SOFT: Color = Color(0.11, 0.15, 0.25, 0.94)
const BORDER: Color = Color(0.36, 0.70, 0.98, 0.92)
const BORDER_SOFT: Color = Color(0.28, 0.50, 0.82, 0.74)
const ACCENT: Color = Color(0.23, 0.95, 0.95, 1.0)
const ACCENT_SOFT: Color = Color(0.49, 0.69, 1.0, 1.0)
const DANGER: Color = Color(0.98, 0.33, 0.52, 1.0)
const TEXT_PRIMARY: Color = Color(0.90, 0.97, 1.0, 1.0)
const TEXT_SECONDARY: Color = Color(0.70, 0.83, 0.96, 0.96)
const TEXT_MUTED: Color = Color(0.54, 0.67, 0.84, 0.96)

static func make_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_SURFACE
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = BORDER_SOFT
	sb.shadow_size = 14
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 12.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 12.0
	return sb

static func make_button_styles() -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BG_SURFACE_SOFT
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = BORDER_SOFT

	var hover := normal.duplicate()
	hover.bg_color = Color(0.15, 0.21, 0.33, 1.0)
	hover.border_color = BORDER
	hover.shadow_size = 5
	hover.shadow_color = Color(0.08, 0.33, 0.58, 0.34)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.07, 0.11, 0.18, 1.0)
	pressed.border_color = ACCENT_SOFT

	var focus := normal.duplicate()
	focus.bg_color = Color(0.14, 0.22, 0.35, 1.0)
	focus.border_color = ACCENT
	focus.border_width_left = 2
	focus.border_width_top = 2
	focus.border_width_right = 2
	focus.border_width_bottom = 2

	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.07, 0.09, 0.13, 0.92)
	disabled.border_color = Color(0.20, 0.30, 0.45, 0.58)

	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"focus": focus,
		"disabled": disabled,
	}

static func make_input_styles() -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.05, 0.08, 0.14, 0.96)
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = BORDER_SOFT
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0

	var focus := normal.duplicate()
	focus.border_color = ACCENT
	focus.border_width_left = 2
	focus.border_width_top = 2
	focus.border_width_right = 2
	focus.border_width_bottom = 2

	return {
		"normal": normal,
		"focus": focus,
	}

static func style_button(button: Button) -> void:
	if button == null:
		return
	var styles: Dictionary = make_button_styles()
	button.add_theme_stylebox_override("normal", styles["normal"])
	button.add_theme_stylebox_override("hover", styles["hover"])
	button.add_theme_stylebox_override("pressed", styles["pressed"])
	button.add_theme_stylebox_override("focus", styles["focus"])
	button.add_theme_stylebox_override("disabled", styles["disabled"])
	button.add_theme_color_override("font_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_focus_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_disabled_color", TEXT_MUTED)
	button.add_theme_font_size_override("font_size", 15)

static func style_panel(panel: PanelContainer) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", make_panel_style())

static func style_line_edit(input: LineEdit) -> void:
	if input == null:
		return
	var styles: Dictionary = make_input_styles()
	input.add_theme_stylebox_override("normal", styles["normal"])
	input.add_theme_stylebox_override("focus", styles["focus"])
	input.add_theme_color_override("font_color", TEXT_PRIMARY)
	input.add_theme_color_override("font_placeholder_color", TEXT_SECONDARY)

static func style_title(label: Label, font_size: int = 28) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_PRIMARY)

static func style_body(label: Label, muted: bool = false) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", TEXT_MUTED if muted else TEXT_SECONDARY)
