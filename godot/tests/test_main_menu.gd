extends SceneTree
## 验证真实主场景切换、局内状态隔离、设置与原有数据流。

var checks := 0
var failures: Array[String] = []
var _quit_requests := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _frames(count: int = 4) -> void:
	for i in count:
		await process_frame

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await _frames()

func _click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
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
	await _frames()

func _button(parent: Node, caption: String) -> Button:
	for node in parent.find_children("*", "Button", true, false):
		if node.text == caption:
			return node
	return null

func _capture(filename: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await _frames()
	await RenderingServer.frame_post_draw
	var path := "res://../验证结果/".path_join(filename)
	_check(root.get_texture().get_image().save_png(path) == OK, "Save viewport capture %s" % filename)

func _run() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.ignore_time_scale = true
	watchdog.timeout.connect(func(): push_error("MENU_INTEGRATION_TIMEOUT"); quit(1))
	root.add_child(watchdog)
	watchdog.start(30.0)
	var timeline := root.get_node("Timeline")
	var keybinds := root.get_node("Keybinds")
	var keys_before: Dictionary = keybinds._keys.duplicate(true)
	var config_existed := FileAccess.file_exists(keybinds.CONFIG_PATH)
	var config_before := FileAccess.get_file_as_bytes(keybinds.CONFIG_PATH) if config_existed else PackedByteArray()
	var volume_before := AudioServer.get_bus_volume_linear(0)
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main_menu.tscn", "Project starts at the menu")
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _frames(8)
	var host := current_scene
	var menu: Control = host.menu
	_check(menu.visible and not paused, "Menu starts visible and responsive")
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "Menu uses window pixels for readable small-window text")
	_check(root.find_children("World", "Node2D", true, false).is_empty(), "No world simulation behind the menu")
	for resolution in [Vector2i(1440, 810), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1024, 768), Vector2i(800, 600), Vector2i(390, 844), Vector2i(320, 240), Vector2i(1920, 480)]:
		root.size = resolution
		await _frames(6)
		var bounds := Rect2(Vector2.ZERO, menu.size)
		_check(bounds.encloses(menu.picture_rect), "Full artwork fits %s" % resolution)
		var previous := Rect2()
		for button in [menu.start_button, menu.settings_button, menu.quit_button]:
			var rect: Rect2 = button.get_global_rect()
			_check(bounds.encloses(rect), "Menu button fits %s / %s" % [resolution, button.text])
			_check(not rect.intersects(previous), "No button overlap %s" % resolution)
			_check(rect.position.y >= menu.picture_rect.position.y + menu.picture_rect.size.y * 0.56, "Title stays clear %s" % resolution)
			previous = rect
		if resolution in [Vector2i(1440, 810), Vector2i(390, 844), Vector2i(320, 240)]:
			await _capture("主界面_%dx%d.png" % [resolution.x, resolution.y])
		menu.open_settings()
		await _frames()
		_check(bounds.encloses(menu._panel.get_global_rect()), "Extended settings fit %s" % resolution)
		if resolution == Vector2i(1440, 810):
			await _capture("菜单设置.png")
		menu.close_settings()
	root.size = Vector2i(1440, 810)
	await _frames()
	menu.start_button.grab_focus()
	await _key(KEY_DOWN)
	_check(root.gui_get_focus_owner() == menu.settings_button, "Keyboard navigates to Settings")
	await _key(KEY_ENTER)
	_check(menu.settings_layer.visible, "Enter opens Settings")
	menu.volume_slider.value = 36
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.36), "Menu applies the master volume")
	if DisplayServer.get_name() != "headless":
		menu.fullscreen_toggle.button_pressed = true
		await _frames(8)
		_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Menu enters actual fullscreen")
		menu.fullscreen_toggle.button_pressed = false
		await _frames(8)
		_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Menu returns to windowed mode")
		root.size = Vector2i(1440, 810)
		await _frames()
	await _click(_button(menu, "按键设置"))
	_check(host.keybind_settings.is_open() and paused and not menu.visible, "Original keybind panel opens modally")
	await _capture("主菜单_按键设置.png")
	keybinds.rebind("attack", 1, KEY_P)
	await _key(KEY_ESCAPE)
	_check(not host.keybind_settings.is_open() and not paused and menu.visible, "Escape closes keybinds and restores the menu")
	_check(menu.settings_layer.visible, "Return from keybinds preserves the Settings page")
	await _key(KEY_ESCAPE)
	_check(not menu.settings_layer.visible, "Escape returns to the three menu entries")
	timeline.set_era(timeline.Era.FUTURE)
	Engine.time_scale = 0.2
	paused = true
	Input.action_press("move_right")
	await _click(menu.start_button)
	await _frames(8)
	var world := current_scene
	world.get_node("DialogueHost").set_process(false) # 剧情事件另由 test_story.gd 验证。
	world.get_node("DialogueHost").dialogue.close_dialogue()
	world.get_node("DialogueHost")._pending.clear()
	_check(world.scene_file_path == "res://scenes/world.tscn", "Start loads the original World as current_scene")
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and root.content_scale_size == Vector2i(720, 405), "Gameplay keeps its original pixel canvas and stretch")
	_check(not is_instance_valid(host), "Menu host is released on start")
	_check(not paused and is_equal_approx(Engine.time_scale, 1.0), "Start clears time stop and slow motion")
	_check(not timeline.is_future(), "Start resets the global timeline to Modern")
	_check(not Input.is_action_pressed("move_right"), "Start clears lingering gameplay input")
	_check(keybinds.keycode_of("attack", 1) == KEY_P, "New run preserves custom keybinds")
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.36), "New run preserves volume")
	var player: Node2D = world.player
	_check(player.position.is_equal_approx(world.spawn_position), "Player starts at the original spawn")
	_check(player.hp == player.hp_max and player.stamina == player.stamina_max, "Player starts with full stats")
	_check(world.get_node("HUD/BossHud")._find_boss() == world.get_node("YSort/FutureBoss"), "Boss HUD still resolves through current_scene")
	await _capture("开始游戏_现代.png")
	for i in 6:
		Input.action_press("move_right")
		await physics_frame
	Input.action_release("move_right")
	_check(player.position.x > world.spawn_position.x, "Real gameplay accepts movement after start")
	world.mark_pot_broken(0)
	world.boss_entered = true
	world.modern_boss_defeated = true
	player.has_claw = true
	player.add_talent_points(3)
	player.spend_talent("health")
	player.hp = 1.0
	world.get_node("YSort/ModernEnemy").dead = true
	timeline.toggle()
	_check(world.future_map.visible and not world.modern_map.visible, "Timeline still drives both maps")
	await _capture("游戏_未来.png")
	var old_world := world
	var bullet: Node2D = load("res://scenes/bullet.tscn").instantiate()
	world.ysort.add_child(bullet)
	world.settings.open()
	await _frames()
	_check(paused, "In-game settings still pause the run")
	_check(_button(world.settings, "主菜单") != null, "In-game settings expose the return entry")
	await _capture("游戏内设置_返回入口.png")
	Engine.time_scale = 0.2
	await _click(_button(world.settings, "主菜单"))
	await _frames(8)
	host = current_scene
	if host.scene_file_path != "res://scenes/main_menu.tscn":
		push_error("Return button did not change scene")
		quit(1)
		return
	menu = host.menu
	_check(host.scene_file_path == "res://scenes/main_menu.tscn" and menu.visible, "Return loads the menu scene")
	_check(not is_instance_valid(old_world) and not is_instance_valid(bullet), "Return releases the old world and its projectiles")
	_check(not paused and is_equal_approx(Engine.time_scale, 1.0), "Menu recovers normal process state")
	await _click(menu.start_button)
	await _frames(8)
	world = current_scene
	player = world.player
	_check(not timeline.is_future(), "Repeated start always returns to Modern")
	_check(world.pot_broken == [false, false, false], "New run restores all pot and pylon links")
	_check(not world.boss_entered and not world.modern_boss_defeated and not player.has_claw, "New run resets boss progression and skill unlocks")
	_check(player.talent_points == 0 and player.talent_health == 0 and player.hp_max == player._base_hp_max, "New run resets talent points, investment and max health")
	_check(not world.get_node("YSort/ModernEnemy").dead, "New run restores defeated enemies")
	_check(player.hp == player.hp_max and player.position.is_equal_approx(world.spawn_position), "Repeated start restores player health and spawn")
	_check(keybinds.keycode_of("attack", 1) == KEY_P, "Repeated start still preserves keybind preferences")
	world._return_to_main_menu()
	await _frames(8)
	host = current_scene
	menu = host.menu
	menu.quit_requested.disconnect(host._quit_game)
	menu.quit_requested.connect(func(): _quit_requests += 1)
	await _click(menu.quit_button)
	_check(_quit_requests == 1, "Quit click dispatches exactly once")
	AudioServer.set_bus_volume_linear(0, volume_before)
	keybinds._keys = keys_before
	keybinds.apply_all()
	if config_existed:
		var file := FileAccess.open(keybinds.CONFIG_PATH, FileAccess.WRITE)
		file.store_buffer(config_before)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(keybinds.CONFIG_PATH))
	print("MENU_INTEGRATION_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
