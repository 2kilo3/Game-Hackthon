extends CanvasLayer
## 设置界面：自定义按键（每个动作最多两个键）。
##
## - 打开时暂停游戏（process_mode = ALWAYS，界面照常响应）
## - 每行：动作名 + 两个按键槽；点某个槽进入"按任意键"，按下即生效并落盘
## - 录入时按 Esc 取消、按 Delete/Backspace 清空该槽
## - 底部：恢复默认 / 关闭

signal opened
signal closed

@onready var root: Control = $Root
@onready var grid: GridContainer = $Root/Panel/VBox/Grid
@onready var footer: HBoxContainer = $Root/Panel/VBox/Footer

var _waiting_action := ""
var _waiting_slot := -1
var _slot_buttons := {}   # "action:slot" -> Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_rows()
	Keybinds.changed.connect(_refresh_labels)

func _build_rows() -> void:
	for row in Keybinds.ACTIONS:
		var label := Label.new()
		label.text = row.label
		label.add_theme_font_size_override("font_size", 7)
		label.custom_minimum_size = Vector2(70, 13)
		grid.add_child(label)

		for slot in range(Keybinds.MAX_SLOTS):
			var btn := _make_compact_button()
			btn.custom_minimum_size = Vector2(62, 11)
			btn.pressed.connect(_on_slot_pressed.bind(row.action, slot))
			grid.add_child(btn)
			_slot_buttons["%s:%d" % [row.action, slot]] = btn

	add_footer_button("恢复默认", _on_reset_pressed)
	add_footer_button("关闭", close)
	_refresh_labels()

## 由宿主追加导航入口，按键设置本身不依赖主界面模块。
func add_footer_button(text: String, on_pressed: Callable) -> void:
	var btn := _make_compact_button()
	btn.text = text
	btn.custom_minimum_size = Vector2(84, 12)
	btn.pressed.connect(on_pressed)
	footer.add_child(btn)

## 紧凑按钮：默认 Button 的 StyleBox 内边距太大，8 行放不进 216 高的画布
func _make_compact_button() -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 7)
	btn.add_theme_color_override("font_color", Color(0.88, 0.90, 0.93))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.23, 0.25, 0.29, 1.0)
	sb.border_color = Color(0.45, 0.48, 0.53, 1.0)
	sb.set_border_width_all(1)
	sb.content_margin_left = 3.0
	sb.content_margin_right = 3.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, sb)
	return btn

func _refresh_labels() -> void:
	for row in Keybinds.ACTIONS:
		for slot in range(Keybinds.MAX_SLOTS):
			var btn: Button = _slot_buttons.get("%s:%d" % [row.action, slot])
			if btn == null:
				continue
			if _waiting_action == row.action and _waiting_slot == slot:
				btn.text = "按键…"
			else:
				btn.text = Keybinds.key_text(row.action, slot)

func _on_slot_pressed(action: String, slot: int) -> void:
	_waiting_action = action
	_waiting_slot = slot
	_refresh_labels()

func _on_reset_pressed() -> void:
	_waiting_action = ""
	_waiting_slot = -1
	Keybinds.reset_defaults()
	_refresh_labels()

## 录入按键：只在界面打开时处理
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if _waiting_action != "":
		if event.physical_keycode == KEY_ESCAPE:
			_waiting_action = ""
			_waiting_slot = -1
		elif event.physical_keycode == KEY_DELETE or event.physical_keycode == KEY_BACKSPACE:
			Keybinds.clear_slot(_waiting_action, _waiting_slot)
			_waiting_action = ""
			_waiting_slot = -1
		else:
			Keybinds.rebind(_waiting_action, _waiting_slot, event.physical_keycode)
			_waiting_action = ""
			_waiting_slot = -1
		_refresh_labels()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func open() -> void:
	_waiting_action = ""
	_waiting_slot = -1
	_refresh_labels()
	visible = true
	get_tree().paused = true
	opened.emit()

func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func is_open() -> bool:
	return visible
