extends CanvasLayer
## 本局天赋界面；独占本次暂停，Tab 或 Esc 关闭。

signal opened
signal closed

@onready var player: CharacterBody2D = get_node("../YSort/Player")
@onready var settings: CanvasLayer = get_node("../SettingsMenu")

var remaining_label: Label
var summary_label: Label
var investment_labels := {}
var spend_buttons := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 60
	visible = false
	var root := Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.035, 0.05, 0.82)
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(390, 0)
	center.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.12, 0.17, 1)
	style.border_color = Color(0.35, 0.5, 0.62)
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	panel.add_child(box)
	var title := Label.new()
	title.text = "天赋分配"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	remaining_label = _label(box)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 7)
	box.add_child(grid)
	for row in [["health", "生命值"], ["attack", "攻击力"], ["defense", "防御力"]]:
		var caption := _label(grid)
		caption.text = row[1]
		investment_labels[row[0]] = _label(grid)
		var button := Button.new()
		button.text = "+ 1"
		button.custom_minimum_size = Vector2(70, 24)
		button.add_theme_font_size_override("font_size", 12)
		grid.add_child(button)
		button.pressed.connect(_spend.bind(row[0]))
		spend_buttons[row[0]] = button
	summary_label = _label(box)
	var close_button := Button.new()
	close_button.text = "关闭（Tab / Esc）"
	close_button.custom_minimum_size.y = 26
	close_button.add_theme_font_size_override("font_size", 12)
	box.add_child(close_button)
	close_button.pressed.connect(close)
	player.talents_changed.connect(_refresh)
	settings.opened.connect(_on_settings_opened)
	_refresh()

func _label(parent: Node) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	parent.add_child(label)
	return label

func _refresh() -> void:
	var stats: Dictionary = player.get_talent_stats()
	remaining_label.text = "剩余天赋点：%d" % stats.points
	for key in investment_labels:
		investment_labels[key].text = "已投入 %d" % stats[key]
		spend_buttons[key].disabled = stats.points <= 0 or player.is_dead()
	summary_label.text = "生命上限：%d   每 10 秒恢复：%.1f\n普攻加成：+%d   受到伤害减免：%d\n攻击与防御每 5 点生效 1 点，向下取整" % [stats.hp_max, stats.regen, stats.attack_bonus, stats.damage_reduction]

func _spend(attribute: String) -> void:
	player.spend_talent(attribute)

func open() -> void:
	if visible or settings.is_open() or get_tree().paused or player.is_dead() or player.is_dying() or bool(get_parent().get("_rewinding")):
		return
	_refresh()
	visible = true
	get_tree().paused = true
	spend_buttons.health.grab_focus()
	opened.emit()

func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	closed.emit()

func _on_settings_opened() -> void:
	if visible:
		close()
		get_tree().paused = true

func is_open() -> bool:
	return visible

func _input(event: InputEvent) -> void:
	var host := get_node_or_null("../DialogueHost")
	if host != null and host.is_open():
		return
	if event.is_echo():
		return
	if event.is_action_pressed("toggle_talents"):
		if visible:
			close()
		else:
			open()
		if visible or not get_tree().paused:
			get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
