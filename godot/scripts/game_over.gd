extends Control
## 结束场景不保留 World，黑屏停留；Enter / Esc 可回到主菜单。

func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	for action in Keybinds.ACTIONS:
		Input.action_release(action.action)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		var error := get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		if error != OK:
			push_error("返回主菜单失败：" + error_string(error))
