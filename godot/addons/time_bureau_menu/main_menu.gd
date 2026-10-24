extends Control
## Self-contained view: the host owns the game, audio, window and process.

signal new_game_requested
signal quit_requested
signal settings_opened
signal settings_changed(values: Dictionary)

const BACKGROUND = preload("assets/background.png")
const UI_FONT = preload("assets/TimeBureauSans.ttf")

var start_button: Button
var settings_button: Button
var quit_button: Button
var volume_slider: HSlider
var fullscreen_toggle: CheckButton
var back_button: Button
var settings_layer: ColorRect
var picture_rect := Rect2()
var _background: TextureRect
var _buttons: VBoxContainer
var _panel: PanelContainer
var _settings_box: VBoxContainer
var _volume_text: Label
var _last_focus: Control
var _values := {"master_volume": 1.0, "fullscreen": false}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_theme()
	var backdrop := ColorRect.new()
	backdrop.color = Color("070d18")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background = TextureRect.new()
	_background.texture = BACKGROUND
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	_buttons = VBoxContainer.new()
	add_child(_buttons)
	start_button = _make_button("开始游戏", _buttons)
	settings_button = _make_button("设置", _buttons)
	quit_button = _make_button("退出游戏", _buttons)
	start_button.pressed.connect(func(): new_game_requested.emit())
	settings_button.pressed.connect(open_settings)
	quit_button.pressed.connect(func(): quit_requested.emit())
	_build_settings()
	_link_focus([start_button, settings_button, quit_button])
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)
	_layout()
	start_button.grab_focus.call_deferred()


func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font = UI_FONT
	theme.default_font_size = 24
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(state, "Button", Color.WHITE)
	theme.set_color("font_shadow_color", "Button", Color(0, 0, 0, 0.95))
	theme.set_constant("shadow_offset_y", "Button", 2)
	theme.set_constant("shadow_outline_size", "Button", 4)
	theme.set_stylebox("normal", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("hover", "Button", _style(Color(1, 1, 1, 0.10), 1))
	theme.set_stylebox("pressed", "Button", _style(Color(1, 1, 1, 0.25), 2))
	var focus_style := _style(Color.TRANSPARENT, 1)
	focus_style.border_color = Color(1, 1, 1, 0.55)
	theme.set_stylebox("focus", "Button", focus_style)


func _style(fill: Color, border: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(1, 1, 1, 0.55)
	style.border_width_bottom = border
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style


func _make_button(caption: String, parent: Node) -> Button:
	var button := Button.new()
	button.text = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	return button


func _build_settings() -> void:
	settings_layer = ColorRect.new()
	settings_layer.color = Color(0.015, 0.025, 0.05, 0.87)
	settings_layer.visible = false
	add_child(settings_layer)
	settings_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _style(Color("101a2b"), 1))
	settings_layer.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 16)
	margin.add_child(_settings_box)
	var heading := Label.new()
	heading.text = "设置"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_box.add_child(heading)
	_volume_text = Label.new()
	_settings_box.add_child(_volume_text)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.custom_minimum_size.y = 30
	_settings_box.add_child(volume_slider)
	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.text = "全屏显示"
	fullscreen_toggle.custom_minimum_size.y = 40
	_settings_box.add_child(fullscreen_toggle)
	back_button = _make_button("返回主菜单", _settings_box)
	back_button.custom_minimum_size.y = 44
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(close_settings)
	_link_focus([volume_slider, fullscreen_toggle, back_button])
	set_settings(_values)


func _link_focus(controls: Array) -> void:
	for i in controls.size():
		var control: Control = controls[i]
		var previous: Control = controls[(i - 1 + controls.size()) % controls.size()]
		var following: Control = controls[(i + 1) % controls.size()]
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_previous = control.get_path_to(previous)
		control.focus_neighbor_bottom = control.get_path_to(following)
		control.focus_next = control.get_path_to(following)


## 宿主可以追加已有设置入口；模块不依赖宿主的设置实现。
func add_settings_action(caption: String, callback: Callable) -> Button:
	var button := _make_button(caption, _settings_box)
	button.custom_minimum_size.y = 40
	button.pressed.connect(callback)
	_settings_box.move_child(button, back_button.get_index())
	var controls: Array = []
	for child in _settings_box.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			controls.append(child)
	_link_focus(controls)
	_layout()
	return button


func _layout() -> void:
	if not is_instance_valid(_buttons) or size.x <= 0 or size.y <= 0:
		return
	var font_size := int(clampf(minf(size.x / 1280.0, size.y / 720.0) * 27, 16, 30))
	var button_height := clampf(size.y * 0.075, 32, 58)
	var gap := clampf(size.y * 0.02, 6, 18)
	var menu_height := button_height * 3 + gap * 2
	var image_size := BACKGROUND.get_size()
	var scale_factor := minf(size.x / image_size.x, size.y / image_size.y)
	var shown := image_size * scale_factor
	var top := minf((size.y - shown.y) * 0.5, size.y - 12 - menu_height - shown.y * 0.62)
	# A short window shifts the complete artwork upwards to reserve three hit targets.
	picture_rect = Rect2(Vector2((size.x - shown.x) * 0.5, maxf(0, top)), shown)
	_background.position = picture_rect.position
	_background.size = picture_rect.size
	var menu_width := minf(clampf(shown.x * 0.25, 160, 350), size.x - 24)
	var center_x := picture_rect.position.x + shown.x * 0.235
	_buttons.position = Vector2(clampf(center_x - menu_width * 0.5, 12, size.x - menu_width - 12), picture_rect.position.y + shown.y * 0.62)
	_buttons.size = Vector2(menu_width, menu_height)
	_buttons.add_theme_constant_override("separation", int(gap))
	for button in [start_button, settings_button, quit_button]:
		button.custom_minimum_size.y = button_height
		button.add_theme_font_size_override("font_size", font_size)
	var compact := size.y < 400
	_settings_box.add_theme_constant_override("separation", 6 if compact else 16)
	volume_slider.custom_minimum_size.y = 18 if compact else 30
	for control in _settings_box.get_children():
		control.add_theme_font_size_override("font_size", 16 if compact else 22)
		if control is BaseButton:
			control.custom_minimum_size.y = 28 if compact else (44 if control == back_button else 40)
	_panel.size = Vector2(minf(440, size.x - 24), 0)
	_panel.reset_size()
	_panel.size.x = minf(440, size.x - 24)
	_panel.position = (size - _panel.size) * 0.5


## Values are normalized (volume 0..1); syncing the host never emits changes.
func set_settings(values: Dictionary) -> void:
	_values.master_volume = clampf(float(values.get("master_volume", _values.master_volume)), 0, 1)
	_values.fullscreen = bool(values.get("fullscreen", _values.fullscreen))
	if is_instance_valid(volume_slider):
		volume_slider.set_value_no_signal(_values.master_volume * 100)
		fullscreen_toggle.set_pressed_no_signal(_values.fullscreen)
		_volume_text.text = "主音量  %d%%" % int(round(_values.master_volume * 100))


func get_settings() -> Dictionary:
	return _values.duplicate()


func open_settings() -> void:
	_last_focus = get_viewport().gui_get_focus_owner()
	_buttons.hide()
	settings_layer.show()
	_layout()
	volume_slider.grab_focus()
	settings_opened.emit()


func close_settings() -> void:
	settings_layer.hide()
	_buttons.show()
	if is_instance_valid(_last_focus) and _last_focus.is_visible_in_tree():
		_last_focus.grab_focus()
	else:
		settings_button.grab_focus()


func show_main_menu() -> void:
	show()
	settings_layer.hide()
	_buttons.show()
	start_button.grab_focus()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		var focus := get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus) and is_ancestor_of(focus):
			focus.release_focus()


func _on_volume_changed(value: float) -> void:
	_values.master_volume = value / 100.0
	_volume_text.text = "主音量  %d%%" % int(value)
	settings_changed.emit(get_settings())


func _on_fullscreen_toggled(value: bool) -> void:
	_values.fullscreen = value
	settings_changed.emit(get_settings())


func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and settings_layer.visible and event.is_action_pressed("ui_cancel"):
		close_settings()
		get_viewport().set_input_as_handled()
