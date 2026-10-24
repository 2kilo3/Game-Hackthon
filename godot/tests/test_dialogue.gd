extends SceneTree

var checks := 0
var failures: Array[String] = []
var opens := 0
var closes := 0
var finishes := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func click(button: Button) -> void:
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
	await process_frame

func capture(label: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(label + ".png")) == OK, "save " + label)

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): push_error("dialogue test timeout"); quit(2))
	var dialog = load("res://addons/bureau_dialogue/dialogue.tscn").instantiate()
	root.add_child(dialog)
	await process_frame
	dialog.opened.connect(func(): opens += 1)
	dialog.closed.connect(func(): closes += 1)
	dialog.finished.connect(func(): finishes += 1)
	check(not dialog.is_open() and not paused, "initial closed")
	check(not dialog.advance(), "advance closed is harmless")
	var lines := [{"speaker": "衍月", "text": "衍月的第一句。"}, {"speaker": "特斯拉", "text": "特斯拉回答。"}]
	check(dialog.open_dialogue(lines), "open valid lines")
	check(paused and dialog.visible and opens == 1, "open pauses and signals once")
	lines[0].text = "caller changed"
	check(dialog.current_line().text == "衍月的第一句。", "caller mutation does not change conversation")
	var copy: Dictionary = dialog.current_line()
	copy.text = "changed copy"
	check(dialog.current_line().text == "衍月的第一句。", "getter returns copy")
	check(dialog.portraits[0].texture is AtlasTexture and dialog.portraits[1].texture is AtlasTexture, "upper body atlas crops")
	for i in 2:
		check(dialog.portraits[i].texture.get_height() < dialog.portraits[i].texture.atlas.get_height() * 0.6, "crop upper body " + str(i))
	check(dialog.portraits[0].modulate.r == 1.0 and is_equal_approx(dialog.portraits[1].modulate.r, 0.38), "left speaker bright")
	await capture("对话_衍月")
	await key(KEY_ENTER)
	check(dialog.current_index() == 1 and dialog.current_line().speaker == "特斯拉", "Enter advances exactly once")
	check(dialog.portraits[1].modulate.r == 1.0 and is_equal_approx(dialog.portraits[0].modulate.r, 0.38), "right speaker bright")
	await capture("对话_特斯拉")
	await key(KEY_SPACE)
	check(not dialog.is_open() and not paused and finishes == 1 and closes == 1, "Space finishes and restores running state")
	dialog.close_dialogue()
	check(closes == 1, "duplicate close has no signal")
	for i in 5:
		dialog.open_dialogue(lines)
		dialog.open_dialogue([{"speaker": "衍月", "text": "replacement"}])
		check(dialog.current_index() == 0 and dialog.current_line().text == "replacement", "replace conversation " + str(i))
		dialog.close_dialogue()
		check(not paused, "replacement retains initial pause snapshot " + str(i))
	dialog.open_dialogue(lines)
	await click(dialog.next_button)
	check(dialog.current_index() == 1, "mouse advances exactly once")
	dialog.close_dialogue()
	paused = true
	dialog.open_dialogue(lines)
	dialog.close_dialogue()
	check(paused, "preexisting pause preserved")
	paused = false
	check(not dialog.open_dialogue([{}, 1, {"text": 2}, {"text": "  "}]), "invalid entries rejected")
	check(not paused and dialog.current_index() == -1, "empty input clears state")
	check(dialog.open_dialogue([{}, {"speaker": 123, "text": "旁白"}], {"衍月": "res://missing.png", "特斯拉": null}), "valid line amid invalid lines")
	check(dialog.current_line().speaker == "", "nonstring speaker normalized")
	check(dialog.placeholders[0].visible and dialog.placeholders[1].visible, "missing portraits have placeholders")
	check(is_equal_approx(dialog.portraits[0].modulate.r, 0.38) and is_equal_approx(dialog.portraits[1].modulate.r, 0.38), "narrator dims both")
	check(not dialog.open_dialogue([]) and not paused, "empty replacement closes safely")
	var custom := GradientTexture2D.new()
	dialog.open_dialogue([{"speaker": "特斯拉", "text": "自定义立绘"}], {"特斯拉": custom}, {"特斯拉": "博士"})
	check(dialog.portraits[1].texture == custom and dialog.speaker_label.text == "博士", "custom portrait and name")
	dialog.close_dialogue()
	dialog.finished.connect(func(): dialog.open_dialogue([{"speaker": "衍月", "text": "chain"}]), CONNECT_ONE_SHOT)
	dialog.open_dialogue([{"text": "first"}])
	dialog.advance()
	check(dialog.is_open() and paused and dialog.current_line().text == "chain", "finished callback can open next conversation")
	await key(KEY_ESCAPE)
	check(not dialog.is_open() and not paused, "escape closes chained conversation")
	dialog.open_dialogue(lines)
	dialog.queue_free()
	await process_frame
	check(not paused, "free open standalone module restores pause")
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	# 此测试隔离战斗/界面时钟；事件剧情由 test_story.gd 覆盖。
	world.get_node("DialogueHost").set_process(false)
	await process_frame
	var player = world.player
	var host = world.get_node("DialogueHost")
	var talents = world.talents
	lines[0].text = "【模块验证】对话期间游戏暂停，衍月正在说话。"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.claw_cooldown_left = 3.0
	var pos: Vector2 = player.position
	host.open_dialogue(lines)
	check(player.process_mode == Node.PROCESS_MODE_DISABLED, "host disables ALWAYS player")
	await create_timer(0.2, true).timeout
	check(player.claw_cooldown_left == 3.0 and player.position == pos, "player position and cooldown frozen")
	await key(KEY_TAB)
	check(not talents.visible and paused and host.is_open(), "Tab cannot open talents beneath dialogue")
	await capture("游戏内对话")
	host.dialogue.close_dialogue()
	check(player.process_mode == Node.PROCESS_MODE_ALWAYS and not paused, "host restores original process mode")
	player.process_mode = Node.PROCESS_MODE_INHERIT
	talents.open()
	host.open_dialogue(lines)
	await key(KEY_TAB)
	check(talents.visible and host.is_open() and paused, "API overlay cannot close underlying talent pause")
	host.dialogue.close_dialogue()
	check(paused and talents.visible, "closing overlay preserves underlying modal")
	talents.close()
	world.settings.open()
	await key(KEY_F8)
	check(not host.is_open() and paused, "F8 has no dialogue action above settings")
	world.settings.close()
	await key(KEY_F8)
	check(not host.is_open() and not paused and not InputMap.has_action("dialogue_demo"), "F8 binding and demo entry removed")
	world.set_process(false)
	for child in world.ysort.get_children():
		if child != player:
			child.process_mode = Node.PROCESS_MODE_DISABLED
	var boss = world.get_node("YSort/ModernBoss")
	var pylon = world.get_node("YSort/EnergyPylon1")
	boss.damage_poise(boss.poise_max)
	pylon._activate()
	root.get_node("Timeline").set_era(1)
	world._start_future_boss_transform()
	host.open_dialogue(lines)
	await create_timer(2.2, true).timeout
	check(boss.poise == 0.0, "boss stagger coroutine stays paused")
	check(pylon.sprite.animation == "activate", "pylon activation coroutine stays paused")
	check(world._boss_transform_running and is_instance_valid(world._boss_transform_actor), "transformation coroutine stays paused")
	host.dialogue.close_dialogue()
	await create_timer(3.3).timeout
	check(boss.poise == boss.poise_max, "boss stagger resumes")
	check(pylon.sprite.animation == "active", "pylon activation resumes")
	check(not world._boss_transform_running, "transformation resumes")
	player.state = "block"
	player.block_phase = "in"
	player._start_perfect_block()
	var block_time: float = player.perfect_block_time
	host.open_dialogue(lines)
	await create_timer(0.2, true).timeout
	check(player.perfect_block_time == block_time and paused, "actual perfect block freezes during dialogue")
	host.dialogue.close_dialogue()
	check(paused and player.process_mode == Node.PROCESS_MODE_ALWAYS, "actual perfect block state resumes")
	await create_timer(1.5, true).timeout
	check(not paused and player.process_mode == Node.PROCESS_MODE_INHERIT, "perfect block completes after dialogue")
	host.open_dialogue(lines)
	host.dialogue.queue_free()
	await process_frame
	check(not paused and player.process_mode == Node.PROCESS_MODE_INHERIT, "removing open module restores host")
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	await create_timer(0.15).timeout
	world.queue_free()
	await process_frame
	print("DIALOGUE_RESULT ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
