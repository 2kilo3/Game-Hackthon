extends Control
## 主界面接入层：菜单只发请求，真实关卡仍以 World 作为 current_scene。

const MENU_PATH := "res://addons/time_bureau_menu/main_menu.tscn"
const GAME_PATH := "res://scenes/world.tscn"

@onready var keybind_settings: CanvasLayer = $KeybindSettings

var menu: Control
var _starting := false
var _game_scale_mode: Window.ContentScaleMode

func _ready() -> void:
	# 离开战斗后清理时停、慢动作与残留输入，不改键位配置。
	get_tree().paused = false
	Engine.time_scale = 1.0
	# 菜单按窗口像素布局，进入游戏时恢复原有的像素画布缩放。
	_game_scale_mode = get_window().content_scale_mode
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for row in Keybinds.ACTIONS:
		Input.action_release(row.action)
	if not ResourceLoader.exists(MENU_PATH):
		start_new_game.call_deferred()
		return
	var scene := load(MENU_PATH) as PackedScene
	if scene == null:
		push_warning("主界面加载失败，直接进入游戏")
		start_new_game.call_deferred()
		return
	menu = scene.instantiate()
	add_child(menu)
	menu.new_game_requested.connect(start_new_game)
	menu.quit_requested.connect(_quit_game)
	menu.settings_changed.connect(_apply_settings)
	menu.settings_opened.connect(_sync_settings)
	var keybind_button: Button = menu.add_settings_action("按键设置", _open_keybinds)
	keybind_button.add_theme_font_override("font", preload("res://assets/fonts/ui_noto.otf"))
	keybind_settings.closed.connect(_close_keybinds)
	_sync_settings()

func start_new_game() -> void:
	if _starting:
		return
	_starting = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	Timeline.reset()
	for row in Keybinds.ACTIONS:
		Input.action_release(row.action)
	get_window().content_scale_mode = _game_scale_mode
	var err := get_tree().change_scene_to_file(GAME_PATH)
	if err != OK:
		_starting = false
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		push_error("开始游戏失败：%s" % error_string(err))

func _sync_settings() -> void:
	var mode := DisplayServer.window_get_mode()
	menu.set_settings({
		"master_volume": AudioServer.get_bus_volume_linear(0),
		"fullscreen": mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	})

func _apply_settings(values: Dictionary) -> void:
	AudioServer.set_bus_volume_linear(0, values.master_volume)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _open_keybinds() -> void:
	menu.hide()
	keybind_settings.open()

func _close_keybinds() -> void:
	menu.show()
	menu.open_settings()

func _quit_game() -> void:
	get_tree().quit()
