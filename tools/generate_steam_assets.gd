@tool
extends Node2D
## Generates Steam store and library placeholder PNGs for Ironwake Playtest.
## Inspector: use **Generate all Steam PNGs**. Or run this scene as main (play / MCP); it exports then quits.

const STEAM_DIR := "res://steam_assets/"

const FILES := {
	"header_capsule.png": Vector2i(920, 430),
	"small_capsule.png": Vector2i(462, 174),
	"main_capsule.png": Vector2i(1232, 706),
	"library_capsule.png": Vector2i(600, 900),
	"library_header.png": Vector2i(920, 430),
	"library_hero.png": Vector2i(3840, 1240),
	"library_logo.png": Vector2i(1280, 720),
	"app_icon.png": Vector2i(256, 256),
}

@export_tool_button("Generate all Steam PNGs", "Writes PNGs into res://steam_assets/")
var generate_steam_pngs: Callable = func() -> void:
	_generate_async()


func _generate_async() -> void:
	if not is_inside_tree():
		push_error("SteamImageGenerator must be in the scene tree.")
		return
	await _run_all_exports()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var st := get_tree() as SceneTree
	if st != null and st.current_scene == self:
		await _run_all_exports()
		st.quit()


func _run_all_exports() -> void:
	_ensure_output_dir()
	await _export_header_capsule()
	await _export_small_capsule()
	await _export_main_capsule()
	await _export_library_capsule()
	await _export_library_header()
	await _export_library_hero()
	await _export_library_logo()
	await _export_app_icon()
	print("Steam assets written to ", STEAM_DIR)
	for file_key: String in FILES:
		var path: String = STEAM_DIR + file_key
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			push_error("Missing or unreadable: ", path)
		else:
			var expected: Vector2i = FILES[file_key]
			if img.get_width() != expected.x or img.get_height() != expected.y:
				push_error(
					"Wrong size for %s: got %dx%d, want %dx%d"
					% [file_key, img.get_width(), img.get_height(), expected.x, expected.y]
				)
			else:
				print("OK ", file_key, " ", expected.x, "x", expected.y)


func _ensure_output_dir() -> void:
	var abs_dir := ProjectSettings.globalize_path(STEAM_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		return
	var err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if err != OK:
		push_error("Failed to create steam_assets: ", abs_dir, " err=", err)


func _make_title_font() -> Font:
	var f := SystemFont.new()
	f.font_weight = 800
	f.font_italic = false
	return f


func _add_linear_gradient_bg(parent: Control, top: Color, bottom: Color) -> void:
	var texture_rect := TextureRect.new()
	texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, top)
	grad.set_color(1, bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = maxi(2, int(parent.size.x))
	gt.height = maxi(2, int(parent.size.y))
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	texture_rect.texture = gt
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	parent.add_child(texture_rect)


func _add_vignette(parent: Control, strength: float = 0.55) -> void:
	var texture_rect := TextureRect.new()
	texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, strength))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = maxi(2, int(parent.size.x))
	gt.height = maxi(2, int(parent.size.y))
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	texture_rect.texture = gt
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	parent.add_child(texture_rect)


func _add_border_panel(parent: Control) -> void:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.42, 0.48, 0.58, 0.5)
	panel.add_theme_stylebox_override(&"panel", sb)
	parent.add_child(panel)


func _add_title_block(
	parent: Control,
	title_px: int,
	sub_px: int,
	show_subtitle: bool,
	title_color: Color = Color(0.9, 0.93, 0.97),
	sub_color: Color = Color(0.65, 0.72, 0.82)
) -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override(&"separation", maxi(4, int(floor(sub_px / 4.0))))
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vb)
	var font := _make_title_font()
	var title := Label.new()
	title.text = "IRONWAKE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override(&"font", font)
	title.add_theme_font_size_override(&"font_size", title_px)
	title.add_theme_color_override(&"font_color", title_color)
	vb.add_child(title)
	if show_subtitle:
		var sub := Label.new()
		sub.text = "PLAYTEST"
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_override(&"font", font)
		sub.add_theme_font_size_override(&"font_size", sub_px)
		sub.add_theme_color_override(&"font_color", sub_color)
		vb.add_child(sub)


func _fit_title_size(text: String, font: Font, max_w: float, max_h: float, start: int) -> int:
	var px := start
	while px > 10:
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, px)
		if sz.x <= max_w * 0.94 and sz.y <= max_h * 0.88:
			return px
		px -= 2
	return 10


func _render_viewport_png(
	size: Vector2i,
	transparent: bool,
	build: Callable
) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = transparent
	vp.disable_3d = true
	vp.handle_input_locally = false
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var root := Control.new()
	root.position = Vector2.ZERO
	root.custom_minimum_size = Vector2(size)
	root.size = Vector2(size)
	vp.add_child(root)
	build.call(root)
	await get_tree().process_frame
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var tex := vp.get_texture()
	var img: Image = tex.get_image()
	remove_child(vp)
	vp.queue_free()
	if img == null:
		return null
	return img


func _save_png(rel_path: String, img: Image) -> void:
	if img == null:
		push_error("No image for ", rel_path)
		return
	var path := ProjectSettings.globalize_path(STEAM_DIR + rel_path)
	var err := img.save_png(path)
	if err != OK:
		push_error("save_png failed ", rel_path, " err=", err)


func _export_header_capsule() -> void:
	var size: Vector2i = FILES["header_capsule.png"]
	var img := await _render_viewport_png(size, false, func(root: Control) -> void:
		_add_linear_gradient_bg(
			root,
			Color(0.07, 0.1, 0.16),
			Color(0.02, 0.03, 0.06)
		)
		_add_vignette(root, 0.5)
		_add_title_block(root, int(size.y * 0.26), int(size.y * 0.065), true)
		_add_border_panel(root)
	)
	_save_png("header_capsule.png", img)


func _export_small_capsule() -> void:
	var size: Vector2i = FILES["small_capsule.png"]
	var font := _make_title_font()
	var title_px := _fit_title_size("IRONWAKE", font, float(size.x), float(size.y) * 0.78, int(size.y * 0.48))
	var sub_px := maxi(10, int(size.y * 0.16))
	var img := await _render_viewport_png(size, false, func(root: Control) -> void:
		_add_linear_gradient_bg(
			root,
			Color(0.06, 0.09, 0.15),
			Color(0.015, 0.02, 0.045)
		)
		_add_vignette(root, 0.45)
		_add_title_block(root, title_px, sub_px, true)
		_add_border_panel(root)
	)
	_save_png("small_capsule.png", img)


func _export_main_capsule() -> void:
	var size: Vector2i = FILES["main_capsule.png"]
	var img := await _render_viewport_png(size, false, func(root: Control) -> void:
		_add_linear_gradient_bg(
			root,
			Color(0.09, 0.11, 0.18),
			Color(0.02, 0.025, 0.055)
		)
		# Subtle "key art" diagonal warmth (no awards / quotes).
		var slash := ColorRect.new()
		slash.set_anchors_preset(Control.PRESET_FULL_RECT)
		slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slash.rotation = deg_to_rad(-18.0)
		slash.pivot_offset = Vector2(size) * 0.5
		slash.color = Color(0.42, 0.26, 0.14, 0.14)
		root.add_child(slash)
		_add_vignette(root, 0.52)
		_add_title_block(root, int(size.y * 0.22), int(size.y * 0.055), true)
		_add_border_panel(root)
	)
	_save_png("main_capsule.png", img)


func _export_library_capsule() -> void:
	var size: Vector2i = FILES["library_capsule.png"]
	var img := await _render_viewport_png(size, false, func(root: Control) -> void:
		_add_linear_gradient_bg(
			root,
			Color(0.05, 0.08, 0.14),
			Color(0.02, 0.03, 0.07)
		)
		_add_vignette(root, 0.48)
		_add_title_block(root, int(size.x * 0.14), int(size.x * 0.045), true)
		_add_border_panel(root)
	)
	_save_png("library_capsule.png", img)


func _export_library_header() -> void:
	var size: Vector2i = FILES["library_header.png"]
	var img := await _render_viewport_png(size, false, func(root: Control) -> void:
		_add_linear_gradient_bg(
			root,
			Color(0.07, 0.1, 0.16),
			Color(0.02, 0.03, 0.06)
		)
		_add_vignette(root, 0.5)
		_add_title_block(root, int(size.y * 0.26), int(size.y * 0.065), true)
		_add_border_panel(root)
	)
	_save_png("library_header.png", img)


func _export_library_hero() -> void:
	var size: Vector2i = FILES["library_hero.png"]
	var img := await _render_viewport_png(size, false, func(root: Control) -> void:
		_add_linear_gradient_bg(
			root,
			Color(0.04, 0.06, 0.11),
			Color(0.015, 0.02, 0.04)
		)
		# Soft center emphasis (~860x380 safe region) — no text or logos.
		var cx := root.size.x * 0.5
		var cy := root.size.y * 0.5
		var glow := TextureRect.new()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.position = Vector2(cx - root.size.x * 0.22, cy - root.size.y * 0.15)
		glow.size = Vector2(root.size.x * 0.44, root.size.y * 0.3)
		var grad := Gradient.new()
		grad.set_color(0, Color(0.12, 0.16, 0.24, 0.22))
		grad.set_color(1, Color(0, 0, 0, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 512
		gt.height = 512
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		glow.texture = gt
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.stretch_mode = TextureRect.STRETCH_SCALE
		root.add_child(glow)
		# Distant horizon band.
		var band := ColorRect.new()
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.set_anchor(SIDE_LEFT, 0.0)
		band.set_anchor(SIDE_TOP, 0.58)
		band.set_anchor(SIDE_RIGHT, 1.0)
		band.set_anchor(SIDE_BOTTOM, 0.62)
		band.offset_left = 0.0
		band.offset_top = 0.0
		band.offset_right = 0.0
		band.offset_bottom = 0.0
		band.color = Color(0.08, 0.12, 0.2, 0.35)
		root.add_child(band)
		_add_vignette(root, 0.58)
		_add_border_panel(root)
	)
	_save_png("library_hero.png", img)


func _export_library_logo() -> void:
	var size: Vector2i = FILES["library_logo.png"]
	var img := await _render_viewport_png(size, true, func(root: Control) -> void:
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(center)
		var font := _make_title_font()
		var title := Label.new()
		title.text = "IRONWAKE"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_override(&"font", font)
		title.add_theme_font_size_override(&"font_size", int(size.y * 0.2))
		title.add_theme_color_override(&"font_color", Color(0.9, 0.93, 0.97))
		title.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.75))
		title.add_theme_constant_override(&"shadow_offset_x", 6)
		title.add_theme_constant_override(&"shadow_offset_y", 6)
		title.add_theme_constant_override(&"outline_size", 2)
		title.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.45))
		center.add_child(title)
	)
	_save_png("library_logo.png", img)


func _export_app_icon() -> void:
	var size: Vector2i = FILES["app_icon.png"]
	var img := await _render_viewport_png(size, false, func(root: Control) -> void:
		var panel := Panel.new()
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.08, 0.14)
		sb.set_corner_radius_all(48)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.35, 0.42, 0.55, 0.85)
		panel.add_theme_stylebox_override(&"panel", sb)
		root.add_child(panel)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(center)
		var font := _make_title_font()
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override(&"separation", -6)
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		center.add_child(hb)
		var t_i := Label.new()
		t_i.text = "I"
		t_i.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t_i.add_theme_font_override(&"font", font)
		t_i.add_theme_font_size_override(&"font_size", 168)
		t_i.add_theme_color_override(&"font_color", Color(0.92, 0.94, 0.98))
		hb.add_child(t_i)
		var t_w := Label.new()
		t_w.text = "W"
		t_w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t_w.add_theme_font_override(&"font", font)
		t_w.add_theme_font_size_override(&"font_size", 140)
		t_w.add_theme_color_override(&"font_color", Color(0.78, 0.82, 0.9))
		hb.add_child(t_w)
	)
	_save_png("app_icon.png", img)
