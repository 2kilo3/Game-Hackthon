extends Node
## 按键绑定管理（autoload 名：Keybinds）
##
## - 每个动作最多 **两个按键**（同一个功能可以同时绑定两个键）
## - 默认一套键位（例如闪避 = Shift + L，移动 = WASD + 方向键）
## - 启动时读取 user://keybinds.cfg，覆盖默认值
## - 统一把绑定写进 InputMap（项目设置里的 [input] 段不用手写）
## - 设置界面通过 rebind(action, slot, keycode) / reset_defaults() 修改，改动立刻生效并落盘

const CONFIG_PATH := "user://keybinds.cfg"
## 配置版本：键位默认值改动时 +1，读档时版本不一致就忽略旧配置、回到新默认
const CONFIG_VERSION := 2
## 每个动作最多几个按键
const MAX_SLOTS := 2

## 动作 -> 默认键（数组长度 = MAX_SLOTS）+ 显示名；顺序即设置界面的顺序
const ACTIONS := [
	{ "action": "move_up", "label": "移动：上", "keys": [KEY_W, KEY_UP] },
	{ "action": "move_down", "label": "移动：下", "keys": [KEY_S, KEY_DOWN] },
	{ "action": "move_left", "label": "移动：左", "keys": [KEY_A, KEY_LEFT] },
	{ "action": "move_right", "label": "移动：右", "keys": [KEY_D, KEY_RIGHT] },
	{ "action": "dodge", "label": "闪避", "keys": [KEY_SHIFT, KEY_L] },
	{ "action": "attack", "label": "普通攻击", "keys": [KEY_J, 0] },
	{ "action": "block", "label": "格挡", "keys": [KEY_K, 0] },
	{ "action": "claw", "label": "钩爪", "keys": [KEY_Q, 0] },
	{ "action": "switch_time", "label": "切换时空", "keys": [KEY_R, 0] },
	{ "action": "toggle_debug", "label": "调试信息", "keys": [KEY_F1, 0] },
	{ "action": "toggle_settings", "label": "设置界面", "keys": [KEY_ESCAPE, 0] },
	{ "action": "toggle_talents", "label": "天赋界面", "keys": [KEY_TAB, 0] },
]

## 调试用动作：也注册进 InputMap，但不参与自定义
const EXTRA_ACTIONS := [
	{ "action": "debug_damage", "key": KEY_F3 },
	{ "action": "debug_poise", "key": KEY_F4 },
	{ "action": "debug_heal", "key": KEY_F5 },
	{ "action": "debug_kill", "key": KEY_F6 },
	{ "action": "debug_hit_dummy", "key": KEY_F7 },
]

## 绑定变化的信号（设置界面用来刷新文字）
signal changed

var _keys := {}   # action -> [keycode, keycode]（0 表示这个槽位没绑定）

func _ready() -> void:
	reset_to_defaults(false)
	load_config()
	apply_all()

func default_keys(action: String) -> Array:
	for row in ACTIONS:
		if row.action == action:
			return row.keys.duplicate()
	return []

func label_of(action: String) -> String:
	for row in ACTIONS:
		if row.action == action:
			return row.label
	return action

## 某个槽位的键码（0 = 未绑定）
func keycode_of(action: String, slot: int = 0) -> int:
	var arr: Array = _keys.get(action, [])
	if slot < 0 or slot >= arr.size():
		return 0
	return int(arr[slot])

## 某个动作的所有键码（过滤掉未绑定的）
func keycodes_of(action: String) -> Array:
	var out := []
	var arr: Array = _keys.get(action, [])
	for k in arr:
		if int(k) != 0:
			out.append(int(k))
	return out

## 按键显示文本（未绑定显示 "—"）
func key_text(action: String, slot: int = 0) -> String:
	var code := keycode_of(action, slot)
	if code == 0:
		return "—"
	return OS.get_keycode_string(code)

## 设置某个槽位的按键。
## 如果这个键已经被别的动作/槽位占用，就把对方的那个槽位改成当前槽位原来的键（互相交换），
## 保证总有一个键不会凭空丢失。
func rebind(action: String, slot: int, keycode: int) -> void:
	if action == "" or keycode == 0:
		return
	if slot < 0 or slot >= MAX_SLOTS:
		return
	if not _keys.has(action):
		_keys[action] = [0, 0]
	var old: int = int(_keys[action][slot])
	for other in _keys.keys():
		for i in range(MAX_SLOTS):
			if int(_keys[other][i]) == keycode:
				_keys[other][i] = old
				_apply_action(other)
	_keys[action][slot] = keycode
	_apply_action(action)
	save_config()
	changed.emit()

## 清空某个槽位
func clear_slot(action: String, slot: int) -> void:
	if not _keys.has(action) or slot < 0 or slot >= MAX_SLOTS:
		return
	_keys[action][slot] = 0
	_apply_action(action)
	save_config()
	changed.emit()

func reset_defaults() -> void:
	reset_to_defaults(true)
	save_config()
	changed.emit()

func reset_to_defaults(apply: bool) -> void:
	_keys.clear()
	for row in ACTIONS:
		var arr := [0, 0]
		var defaults: Array = row.keys
		for i in range(mini(MAX_SLOTS, defaults.size())):
			arr[i] = int(defaults[i])
		_keys[row.action] = arr
	if apply:
		apply_all()

# ---------------- 内部 ----------------
func apply_all() -> void:
	for row in ACTIONS:
		_apply_action(row.action)
	for row in EXTRA_ACTIONS:
		if not InputMap.has_action(row.action):
			InputMap.add_action(row.action, 0.2)
		InputMap.action_erase_events(row.action)
		var ev := InputEventKey.new()
		ev.physical_keycode = row.key
		InputMap.action_add_event(row.action, ev)

func _apply_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	InputMap.action_erase_events(action)
	for code in keycodes_of(action):
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		InputMap.action_add_event(action, ev)

func save_config() -> void:
	var cfg := ConfigFile.new()
	for action in _keys.keys():
		var arr: Array = _keys[action]
		for i in range(MAX_SLOTS):
			cfg.set_value("keys", "%s_%d" % [action, i], int(arr[i]))
	cfg.set_value("meta", "version", CONFIG_VERSION)
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("保存按键配置失败：%s" % err)

## 没有配置文件时保持默认；兼容旧版"一个动作一个键"的格式
func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	# 旧版本的存档（比如闪避还是 Shift+空格 的那套）直接作废
	if int(cfg.get_value("meta", "version", 1)) != CONFIG_VERSION:
		return
	for action in _keys.keys():
		var arr: Array = _keys[action]
		for i in range(MAX_SLOTS):
			var key_name := "%s_%d" % [action, i]
			if cfg.has_section_key("keys", key_name):
				arr[i] = int(cfg.get_value("keys", key_name))
			elif i == 0 and cfg.has_section_key("keys", action):
				# 旧格式：keys/<action> = keycode
				arr[0] = int(cfg.get_value("keys", action))
