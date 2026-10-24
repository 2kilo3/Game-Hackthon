extends SceneTree
## 独立运行版退出验证，或在不含菜单目录的副本中验证降级启动。

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.ignore_time_scale = true
	watchdog.timeout.connect(func(): push_error("MENU_SMOKE_TIMEOUT"); quit(1))
	root.add_child(watchdog)
	watchdog.start(20.0)
	root.size = Vector2i(1440, 810)
	change_scene_to_file("res://scenes/main_menu.tscn")
	for i in 10:
		await process_frame
	if OS.get_cmdline_user_args().has("--without-menu"):
		assert(not ResourceLoader.exists("res://addons/time_bureau_menu/main_menu.tscn"))
		assert(current_scene.scene_file_path == "res://scenes/world.tscn")
		assert(not paused and is_equal_approx(Engine.time_scale, 1.0))
		var player: Node2D = current_scene.player
		var start := player.position
		Input.action_press("move_right")
		for i in 8:
			await physics_frame
		Input.action_release("move_right")
		assert(player.position.x > start.x)
		for i in 4:
			await process_frame
		print("MENU_REMOVAL_PASSED: original World starts and accepts movement")
		quit.call_deferred(0)
		return
	var menu: Control = current_scene.menu
	assert(menu.visible)
	var point: Vector2 = menu.quit_button.get_global_rect().get_center()
	print("NATIVE_QUIT_CLICK: dispatching mouse input to the real quit button")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
