extends SceneTree
## 真实 World 信号、战斗入口、穿梭/回溯动画与原对话 UI 的端到端剧情验证。

var checks := 0
var failures: Array[String] = []
var played: Array[String] = []
var world
var host
var player

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int = 1) -> void:
	for i in count:
		await physics_frame
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func fresh(via_menu: bool = false) -> void:
	if via_menu:
		current_scene.start_new_game()
		await frames(8)
		world = current_scene
	else:
		root.get_node("Timeline").reset()
		world = load("res://scenes/world.tscn").instantiate()
		root.add_child(world)
		current_scene = world
	host = world.get_node("DialogueHost")
	player = world.player
	# 保留真实信号/动画与角色物理，仅固定敌人，避免随机战斗干扰事件顺序。
	world.set_process(false)
	for entity in world.ysort.get_children():
		if entity != player:
			entity.set_physics_process(false)
	host.dialogue.opened.connect(func(): played.append(host._current_story))
	await frames(2)

func wait_story(id: String, limit: int = 300) -> void:
	for i in limit:
		if host.is_open():
			break
		await frames()
	check(host.is_open() and host._current_story == id, "Passive trigger: " + id)
	check(paused and player.process_mode == Node.PROCESS_MODE_DISABLED, "Story pauses gameplay: " + id)
	check(host.dialogue.current_index() == 0, "Starts at first line: " + id)

func finish_story(id: String) -> void:
	var lines: Array = host.dialogue._lines.duplicate(true)
	for line in lines:
		check(host.dialogue.current_line() == line, "Displayed source line: " + id + " / " + str(host.dialogue.current_index()))
		if id == "talents_closed" and host.dialogue.current_index() == 4:
			await capture("03b_长台词排版")
		host.dialogue.advance()
	check(not host.is_open() and not paused, "Normal end restores pause: " + id)
	await frames(2)

func capture(name: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(name + ".png")) == OK, "Screenshot: " + name)

func rewind_player() -> void:
	player.start_death()
	var stayed_closed := true
	for i in 300:
		if not player.is_dead() and not world._rewinding and not player.is_dying():
			check(stayed_closed, "No story during death/rewind")
			return
		stayed_closed = stayed_closed and not host.is_open()
		await frames()
	check(false, "Rewind completed before timeout")

func release_world() -> void:
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	world.queue_free()
	await frames(2)
	current_scene = null

func finish_ending(skip: bool) -> void:
	var old_world: Node = world
	if skip:
		await key(KEY_ESCAPE)
		check(host.is_open() and host.dialogue.current_line().text == "（未完待续）" and paused, "Skipping ending still shows epilogue and keeps combat paused")
	else:
		while host.dialogue.current_line().text != "（未完待续）":
			host.dialogue.advance()
		check(host.is_open() and not host._ending and paused, "Epilogue stays visible until player continues")
	await capture("07_未完待续")
	var old_position: Vector2 = player.position
	host.dialogue.advance()
	check(host._ending and paused and host._pending.is_empty(), "Closing epilogue begins one fade and clears future events")
	host.queue_story("pot_broken")
	check(host._pending.is_empty() and not host.open_dialogue([{"speaker":"", "text":"late"}]), "Late story calls cannot overwrite ending")
	await frames(10)
	check(is_instance_valid(old_world) and host._fade.modulate.a > 0 and host._fade.modulate.a < 1, "Black overlay fades progressively")
	check(player.position == old_position and player.process_mode == Node.PROCESS_MODE_DISABLED, "Player remains frozen through fade")
	await capture("08_淡出过渡")
	for i in 120:
		if is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/game_over.tscn":
			break
		await frames()
	check(current_scene.scene_file_path == "res://scenes/game_over.tscn" and not is_instance_valid(old_world), "Full black transitions to a scene with no remaining World")
	check(not paused and Engine.time_scale == 1.0, "Game over releases gameplay pause/slow motion")
	var black = current_scene.get_node("Black")
	var title = black.get_node("Title")
	check(black.color == Color.BLACK and black.size == current_scene.size, "End screen is solid black across viewport")
	check(title.text == "游戏结束" and title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and title.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "Game over caption is centered")
	await key(KEY_R)
	await key(KEY_J)
	await key(KEY_TAB)
	check(current_scene.scene_file_path == "res://scenes/game_over.tscn", "Combat, era and talent input cannot resume the finished game")
	await capture("09_游戏结束")

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): push_error("STORY_TIMEOUT"); quit(2))
	await fresh()
	await wait_story("prologue")
	await capture("00_战前开场")
	await finish_story("prologue")
	await wait_story("battle_start")
	await capture("00b_进战提示")
	await finish_story("battle_start")
	check(not host.is_open() and host._seen.size() == 2, "Opening and combat briefing play once before controls resume")
	check(not InputMap.has_action("dialogue_demo") and not world.hint_label.text.contains("F8"), "F8 binding and HUD hint removed")
	await key(KEY_F8)
	check(not host.is_open(), "F8 cannot open any dialogue")
	await key(KEY_TAB)
	await key(KEY_TAB)
	check(not host._seen.has("talents_closed"), "Pre-pickup talent visits do not consume the story")
	root.get_node("Timeline").set_era(1)
	await frames(2)
	check(not host._seen.has("future_entered") and not host.is_open(), "Early future visit without claw does not consume tutorial")
	root.get_node("Timeline").reset()
	world.mark_pot_broken(-1)
	check(host._pending.is_empty(), "Invalid pot index does not emit story")
	world.get_node("YSort/FlowerPot1").take_damage(1)
	await wait_story("pot_broken")
	await finish_story("pot_broken")
	world.get_node("YSort/FlowerPot1").take_damage(1)
	world.get_node("YSort/FlowerPot2").take_damage(1)
	await frames(2)
	check(played.count("pot_broken") == 1 and not host.is_open(), "Broken pots and later pots do not repeat the same hint")
	var modern = world.get_node("YSort/ModernBoss")
	for enemy in world._entities_modern:
		if enemy != modern:
			enemy.dead = true
	world._check_modern_boss_entrance()
	check(modern._entering and not host._seen.has("modern_boss_appeared"), "Modern boss story waits until walk-in finishes")
	await wait_story("modern_boss_appeared")
	check(modern.spawned and not modern._entering, "Modern boss story follows actual entrance signal")
	modern.set_physics_process(false)
	await capture("00c_现代Boss登场")
	await finish_story("modern_boss_appeared")
	world._check_modern_boss_entrance()
	check(played.count("modern_boss_appeared") == 1, "Modern boss entrance story is not duplicated")
	world.settings.open()
	modern._blocking = false
	modern.take_damage(modern.hp_max)
	check(world.modern_boss_defeated and world.ysort.has_node("ClawPickup"), "Actual modern boss death still rewards/drops claw")
	var pickup = world.ysort.get_node("ClawPickup")
	pickup._on_body_entered(player)
	check(player.has_claw, "Actual pickup handler unlocks claw")
	await frames(3)
	check(not host.is_open() and host._pending == ["modern_boss_defeated", "claw_picked_up"], "Events queue in order during settings pause")
	modern.defeated.emit()
	player.claw_unlocked.emit()
	check(host._pending.size() == 2, "Repeated event signals do not duplicate queued stories")
	world.settings.close()
	await wait_story("modern_boss_defeated")
	check(host.dialogue.current_line().text.contains("核对一次街区的波动"), "Modern victory foreshadows unresolved anomaly")
	await capture("01_现代Boss死亡剧情")
	await key(KEY_ESCAPE)
	await wait_story("claw_picked_up")
	check(played.count("modern_boss_defeated") == 1, "Esc skips current conversation without replay")
	await capture("02_拾取钩爪剧情")
	await finish_story("claw_picked_up")
	await key(KEY_TAB)
	check(world.talents.is_open(), "Talent interaction remains available")
	await key(KEY_TAB)
	await wait_story("talents_closed")
	await capture("03_退出天赋剧情")
	await finish_story("talents_closed")
	await key(KEY_TAB)
	await key(KEY_TAB)
	check(not host.is_open() and played.count("talents_closed") == 1, "Subsequent talent closes do not repeat story")
	player.start_era_shift()
	for i in 150:
		if root.get_node("Timeline").is_future():
			break
		await frames()
	check(player.is_era_shifting() and not host.is_open(), "Future event waits for reappearance, not the shift midpoint")
	await wait_story("future_entered")
	check(not player.is_era_shifting(), "Future tutorial starts after transition completes")
	await finish_story("future_entered")
	root.get_node("Timeline").reset()
	root.get_node("Timeline").set_era(1)
	await frames(2)
	check(not host.is_open() and played.count("future_entered") == 1, "Repeated era switches do not repeat tutorial")
	for entity in world._entities_modern + world._entities_future:
		entity.dead = true
	world._check_boss_entrance()
	check(world._boss_transform_running and not host._seen.has("future_boss_appeared"), "Boss story waits for full transformation")
	await wait_story("future_boss_appeared")
	var boss = world.get_node("YSort/FutureBoss")
	check(boss._entered and not world._boss_transform_running, "Boss story is tied to actual future-form handoff")
	boss.set_physics_process(false)
	await capture("04_未来Boss登场剧情")
	await finish_story("future_boss_appeared")
	world._check_boss_entrance()
	await frames(2)
	check(played.count("future_boss_appeared") == 1, "Repeated boss gate checks do not replay")
	player.kill()
	await rewind_player()
	await frames(2)
	check(not host._seen.has("future_boss_first_death"), "Debug/unattributed death does not consume boss hint")
	# 普通敌人的子弹不能被当作未来 Boss 击杀。
	player.hp = 1
	player.hurt_invuln_left = 0
	var bullet = load("res://scenes/bullet.tscn").instantiate()
	bullet.position = player.position
	bullet.speed = 0
	world.ysort.add_child(bullet)
	await frames(2)
	check(player.is_dead(), "Ordinary bullet still damages player")
	await rewind_player()
	await frames(2)
	check(not host._seen.has("future_boss_first_death"), "Ordinary enemy bullet death is not a boss death")
	player.hp = 1
	player.hurt_invuln_left = 0
	boss._fire(player)
	bullet = world.ysort.get_children().filter(func(node): return node.has_method("is_bullet"))[-1]
	bullet.position = player.position
	bullet.speed = 0
	await frames(2)
	check(player.is_dead() and host._seen.has("future_boss_first_death") and not host.is_open(), "Boss projectile queues hint only on a lethal hit")
	await rewind_player()
	await wait_story("future_boss_first_death")
	check(host.dialogue._lines[2].text.contains("已经打碎过"), "Previously broken pots receive consistent death hint")
	check(not world.rewind.is_playing(), "Death hint appears after rewind overlay is gone")
	await capture("05_首次死亡线索")
	await finish_story("future_boss_first_death")
	boss.player_killed.emit()
	await frames(2)
	check(played.count("future_boss_first_death") == 1 and not host.is_open(), "Further boss deaths never repeat first-death hint")
	boss.shield_up = false
	boss.state = "walk"
	boss.take_damage(boss.hp_max)
	await wait_story("future_boss_defeated")
	await capture("06_第二关结尾")
	check(host._seen.size() == 11 and host._pending.is_empty(), "All eleven event stories reached without omissions")
	await finish_ending(false)
	await key(KEY_ENTER)
	check(current_scene.scene_file_path == "res://scenes/main_menu.tscn", "Enter returns from game over to main menu")
	await fresh(true)
	check(host._seen.size() == 1 and host._seen.has("prologue"), "Menu restart resets progress and starts prologue again")
	await wait_story("prologue")
	await finish_story("prologue")
	await wait_story("battle_start")
	await finish_story("battle_start")
	# 另一局以冲锋致死验证另一条实际伤害入口，并验证非致死命中不提前消耗。
	root.get_node("Timeline").set_era(1)
	boss = world.get_node("YSort/FutureBoss")
	boss.begin_entrance()
	boss.set_physics_process(false)
	boss.position = player.position + Vector2(0, 10)
	boss._start_charge(player)
	boss._update_charge(0, player)
	check(not player.is_dead() and not host._seen.has("future_boss_first_death"), "Nonlethal charge does not consume first-death event")
	player.hp = 1
	player.hurt_invuln_left = 0
	boss._start_charge(player)
	boss._update_charge(0, player)
	check(player.is_dead() and host._seen.has("future_boss_first_death"), "Lethal charge also records actual boss death")
	await rewind_player()
	await wait_story("future_boss_first_death")
	check(host.dialogue._lines[2].text.contains("2026"), "Intact pots receive the original investigation hint")
	await finish_story("future_boss_first_death")
	world.get_node("YSort/FlowerPot1").take_damage(1)
	await wait_story("pot_broken")
	check(played.count("pot_broken") == 2, "New run can trigger same document event again")
	await finish_story("pot_broken")
	player.has_claw = true
	world.talents.open()
	world.talents.close()
	await wait_story("talents_closed")
	check(host.dialogue._lines[5].text.contains("已经在 2209"), "Late talent visit does not tell player to enter Future again")
	await finish_story("talents_closed")
	check(host.STORY.LINES.talents_closed[5].text.contains("立即前往"), "Context variant leaves base data unchanged")
	boss.shield_up = false
	boss.state = "walk"
	boss.take_damage(boss.hp_max)
	await wait_story("future_boss_defeated")
	await finish_ending(true)
	await key(KEY_ESCAPE)
	check(current_scene.scene_file_path == "res://scenes/main_menu.tscn", "Escape returns from black end screen")
	print("STORY_RESULT ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures, "played": played}))
	quit(0 if failures.is_empty() else 1)
