extends CanvasLayer
## 独立对话层；仅持有本次会话开始前的暂停状态。

signal opened
signal closed
signal finished
signal line_changed(speaker: String, text: String, index: int)

const ROLES := ["衍月", "特斯拉"]
const FONT = preload("assets/dialogue_sans.ttf")
const PORTRAITS = [preload("assets/yanyue_full.png"), preload("assets/tesla_full.png")]

var _lines: Array[Dictionary] = []
var _index := -1
var _active := false
var _pause_before := false
var _names := {}
var _root: Control
var panel: PanelContainer
var portraits: Array[TextureRect] = []
var placeholders: Array[Label] = []
var speaker_label: Label
var text_label: Label
var next_button: Button
var scroll: ScrollContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	visible = false
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 14
	_root.theme = theme
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for role in ROLES:
		var portrait := TextureRect.new()
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(portrait)
		portraits.append(portrait)
		var missing := Label.new()
		missing.text = role + "\n立绘未提供"
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_root.add_child(missing)
		placeholders.append(missing)
	panel = PanelContainer.new()
	_root.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.085, 0.97)
	style.border_color = Color(0.43, 0.62, 0.68)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	speaker_label = Label.new()
	speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speaker_label.add_theme_color_override("font_color", Color(0.63, 0.88, 0.9))
	header.add_child(speaker_label)
	var close_button := Button.new()
	close_button.text = "关闭 Esc"
	close_button.add_theme_font_size_override("font_size", 11)
	close_button.pressed.connect(close_dialogue)
	header.add_child(close_button)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(text_label)
	next_button = Button.new()
	next_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	next_button.add_theme_font_size_override("font_size", 11)
	next_button.pressed.connect(advance)
	box.add_child(next_button)
	_root.resized.connect(_layout)
	_layout()

func _layout() -> void:
	if panel == null:
		return
	var size := _root.size
	var width := minf(760.0, maxf(240.0, size.x - 32.0))
	var height := clampf(size.y * 0.32, 135.0, 190.0)
	panel.position = Vector2((size.x - width) / 2.0, size.y - height - 12.0)
	panel.size = Vector2(width, height)
	var portrait_size := Vector2(minf(200.0, width * 0.35), minf(210.0, maxf(80.0, size.y - height - 26.0)))
	for i in 2:
		portraits[i].size = portrait_size
		portraits[i].position = Vector2(panel.position.x + (12.0 if i == 0 else width - portrait_size.x - 12.0), panel.position.y - portrait_size.y + 5.0)
		placeholders[i].position = portraits[i].position
		placeholders[i].size = portrait_size

func open_dialogue(lines: Array, resources: Dictionary = {}, names: Dictionary = {}) -> bool:
	var normalized: Array[Dictionary] = []
	for item in lines:
		if not item is Dictionary or not item.get("text") is String or item.text.strip_edges().is_empty():
			continue
		var speaker: String = item.get("speaker", "") if item.get("speaker", "") is String else ""
		normalized.append({"speaker": speaker, "text": item.text})
	if normalized.is_empty():
		close_dialogue()
		return false
	if not is_node_ready():
		return false
	var was_active := _active
	if not was_active:
		_pause_before = get_tree().paused
	_lines = normalized
	_names = names.duplicate()
	_index = 0
	for i in 2:
		var texture: Texture2D
		if resources.has(ROLES[i]):
			var value = resources[ROLES[i]]
			if value is Texture2D:
				texture = value
			elif value is String and ResourceLoader.exists(value):
				texture = load(value) as Texture2D
		else:
			texture = _upper_body(PORTRAITS[i])
		portraits[i].texture = texture
		placeholders[i].visible = texture == null
	_active = true
	visible = true
	get_tree().paused = true
	if not was_active:
		opened.emit()
	_show_line()
	return true

func _upper_body(texture: Texture2D) -> AtlasTexture:
	var region := Rect2(texture.get_image().get_used_rect())
	region.size.y *= 0.49
	var result := AtlasTexture.new()
	result.atlas = texture
	result.region = region
	return result

func _show_line() -> void:
	var line := _lines[_index]
	speaker_label.text = str(_names.get(line.speaker, line.speaker))
	text_label.text = line.text
	scroll.scroll_vertical = 0
	for i in 2:
		var brightness := 1.0 if line.speaker == ROLES[i] else 0.38
		portraits[i].modulate = Color(brightness, brightness, brightness, 1.0)
		placeholders[i].modulate = portraits[i].modulate
	next_button.text = ("结束" if _index == _lines.size() - 1 else "下一句") + "  ·  Enter / Space   %d / %d" % [_index + 1, _lines.size()]
	line_changed.emit(line.speaker, line.text, _index)

func advance() -> bool:
	if not _active:
		return false
	if _index + 1 >= _lines.size():
		close_dialogue()
		finished.emit()
	else:
		_index += 1
		_show_line()
	return true

func close_dialogue() -> void:
	if not _active:
		return
	_active = false
	visible = false
	_lines.clear()
	_index = -1
	get_tree().paused = _pause_before
	closed.emit()

func is_open() -> bool:
	return _active

func current_index() -> int:
	return _index

func current_line() -> Dictionary:
	return _lines[_index].duplicate() if _active else {}

func _input(event: InputEvent) -> void:
	if not _active or not event is InputEventKey:
		return
	if event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			close_dialogue()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] or event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			advance()
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if _active:
		get_tree().paused = _pause_before
		_active = false
