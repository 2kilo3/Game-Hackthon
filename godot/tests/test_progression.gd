extends SceneTree

var checks := 0
var failures: Array[String] = []
var unlocks := 0

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
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames(2)

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
	create_timer(60.0, true, false, true).timeout.connect(func(): push_error("progression test timeout"); quit(2))
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	# 此测试隔离战斗/界面时钟；事件剧情由 test_story.gd 覆盖。
	world.get_node("DialogueHost").set_process(false)
	await frames(2)
	world.set_process(false)
	world.set_physics_process(false)
	var player = world.player
	var bar = world.get_node("HUD/StatusBars")
	var talents = world.talents
	var mb = world.get_node("YSort/ModernBoss")
	var fb = world.get_node("YSort/FutureBoss")
	for child in world.ysort.get_children():
		if child != player:
			child.process_mode = Node.PROCESS_MODE_DISABLED
	player.claw_unlocked.connect(func(): unlocks += 1)
	check(not player.has_claw and bar.claw_status_text().contains("未获得"), "new run claw locked")
	player._fire_claw()
	check(player.claw_cooldown_left == 0.0, "direct claw API cannot bypass unlock")
	await key(KEY_Q)
	check(player.claw_cooldown_left == 0.0, "Q before pickup cannot fire")
	for enemy in world._entities_modern + world._entities_future:
		if enemy == mb:
			continue
		var before: int = player.talent_points
		enemy._die()
		check(player.talent_points == before + 1, str(enemy.name) + " awards one")
		enemy._die()
		check(player.talent_points == before + 1, str(enemy.name) + " no duplicate reward")
	check(player.talent_points == 8, "eight normal enemies award eight")
	player.position = Vector2(-100, 0)
	mb.position = Vector2(20, 0)
	mb._die()
	check(player.talent_points == 10 and not player.has_claw, "modern boss awards two but no automatic claw")
	var pickup = world.ysort.get_node_or_null("ClawPickup")
	check(pickup != null and pickup.position == mb.position, "pickup drops at boss")
	mb._die()
	check(player.talent_points == 10 and get_nodes_in_group("claw_pickup").size() == 1, "boss repeated death creates no extra reward or pickup")
	await frames(3)
	await capture("钩爪_掉落待拾取")
	player.position = pickup.position
	await frames(4)
	check(player.has_claw and unlocks == 1 and get_nodes_in_group("claw_pickup").is_empty(), "actual Area collision picks up once")
	player.unlock_claw()
	check(unlocks == 1 and bar.claw_status_text().contains("可用"), "unlock idempotent and HUD ready")
	player._fire_claw()
	check(player.claw_cooldown_left > 0.0 and bar.claw_status_text().contains("冷却"), "fire starts visible cooldown")
	player.claw_cooldown_left = 0.01
	check(bar.claw_status_text().contains("0.1s"), "HUD never reports zero while cooling")
	player.claw_cooldown_left = 3.0
	await frames(12)
	check(player.claw_cooldown_left < 2.9 and player.claw_cooldown_left > 2.5, "cooldown ticks in real physics")
	await capture("钩爪_冷却")
	paused = true
	var cooldown: float = player.claw_cooldown_left
	await create_timer(0.2, true).timeout
	check(player.claw_cooldown_left == cooldown, "pause freezes cooldown")
	paused = false
	player.claw_cooldown_left = 0.03
	await frames(5)
	check(player.claw_cooldown_left == 0.0 and bar.claw_status_text().contains("可用"), "cooldown reaches ready")
	fb._die()
	fb._die()
	check(player.talent_points == 12, "future boss awards exactly two")
	var base_max: float = player.hp_max
	var base_hp: float = player.hp
	await key(KEY_TAB)
	check(talents.visible and paused, "Tab opens talent UI and pauses")
	await click(talents.spend_buttons.health)
	check(player.talent_health == 1 and player.hp_max == base_max + 2 and player.hp == base_hp, "health investment adds max two without instant heal")
	check(talents.investment_labels.health.text.contains("1") and talents.remaining_label.text.contains("11"), "UI refreshes invested and remaining")
	check(talents.summary_label.text.contains("0.5"), "UI displays fractional regeneration")
	await capture("天赋_分配")
	await key(KEY_TAB)
	check(not talents.visible and not paused, "Tab closes talent UI")
	world.settings.open()
	talents.open()
	check(not talents.visible and paused, "settings prevents talent opening")
	world.settings.close()
	player.set_physics_process(false)
	player.hp = 10.0
	player._health_regen_elapsed = 0.0
	player._update_talent_regen(9.99)
	check(player.hp == 10, "no regeneration before ten seconds")
	player._update_talent_regen(0.01)
	check(player.hp == 10.5, "one health point regenerates exact half HP")
	player._update_talent_regen(20.0)
	check(player.hp == 11.5, "long delta accounts for each ten seconds")
	player.hp = player.hp_max - 0.1
	player._update_talent_regen(10.0)
	check(player.hp == player.hp_max, "regeneration capped at max")
	player.hp = 0.0
	player._update_talent_regen(10.0)
	check(player.hp == 0.0 and player._health_regen_elapsed == 0.0, "dead player never resurrected by regeneration")
	player.hp = 10.0
	player._health_regen_elapsed = 9.8
	player.set_physics_process(true)
	paused = true
	await create_timer(0.3, true).timeout
	check(player.hp == 10.0 and player._health_regen_elapsed == 9.8, "regeneration uses unpaused game time")
	paused = false
	await frames(15)
	check(player.hp == 10.5, "regeneration resumes on game clock")
	player.set_physics_process(false)
	player.add_talent_points(20)
	var dummy = load("res://scenes/test_dummy.tscn").instantiate()
	dummy.name = "TalentTarget"
	world.ysort.add_child(dummy)
	dummy.position = player.position + Vector2(30, 0)
	dummy.set_physics_process(false)
	player.facing_dir = Vector2.RIGHT
	for child in world.ysort.get_children():
		if child != player and child != dummy and child is CanvasItem:
			child.hide()
	for n in range(1, 11):
		check(player.spend_talent("attack"), "spend attack " + str(n))
		var bonus := floori(n / 5.0)
		check(player.get_talent_stats().attack_bonus == bonus, "attack UI floor " + str(n))
		if n in [4, 5, 9, 10]:
			for stage in [1, 2, 3]:
				player.combo_step = stage
				var base: float = [player.attack_damage, player.attack2_damage, player.attack3_damage][stage - 1]
				check(player._attack_damage() == base + bonus, "attack calculation %d stage %d" % [n, stage])
				dummy.hp = 100.0
				player._do_attack_hit()
				check(dummy.hp == 100.0 - base - bonus, "actual target damage %d stage %d" % [n, stage])
	for n in range(1, 11):
		check(player.spend_talent("defense"), "spend defense " + str(n))
		var reduction := floori(n / 5.0)
		check(player.get_talent_stats().damage_reduction == reduction, "defense UI floor " + str(n))
		if n in [4, 5, 9, 10]:
			player.state = "stand"
			player.hp = 100.0
			player.hurt_invuln_left = 0.0
			player.take_damage(10.0)
			check(player.hp == 90.0 + reduction, "direct damage reduction " + str(n))
			player.hp = 100.0
			player.hurt_invuln_left = 0.0
			player.try_take_hit(10.0)
			check(player.hp == 90.0 + reduction, "combat damage reduction once " + str(n))
			player.hp = 100.0
			player.state = "block"
			player.block_phase = "hold"
			player.perfect_block_used = true
			player.poise = player.poise_max
			player.exhaust_left = 0.0
			player.try_take_hit(10.0, player.position + player.block_side() * 40.0)
			check(player.hp == 100.0 - 10.0 * player.block_damage_multiplier + reduction, "defense after block multiplier " + str(n))
			player.hp = 100.0
			player.hurt_invuln_left = 0.0
			player.try_take_hit(10.0, player.position + player.block_side() * 40.0, true)
			check(player.hp == 90.0 + reduction, "bypass block still applies defense " + str(n))
	Engine.time_scale = 1.0
	player._hitstop_until_ms = 0
	player.state = "stand"
	player.hp = 10.0
	player.hurt_invuln_left = 0.0
	check(not player.take_damage(1.0) and player.hp == 10.0, "defense floor prevents healing or damage")
	check(not player.spend_talent("unknown"), "unknown attribute rejected")
	player.talent_points = 0
	check(not player.spend_talent("health") and player.talent_points == 0, "overspend rejected")
	var health: int = player.talent_health
	player.respawn(Vector2(-100, 0))
	check(player.has_claw and player.talent_health == health and player.hp_max == base_max + 2, "death rewind keeps talents and claw")
	player.set_physics_process(true)
	mb.show()
	mb.position = Vector2(100, -30)
	player.focus_camera_on(mb.position, 1.5, mb)
	var cam: Camera2D = player.get_node("Camera")
	var start: Vector2 = player.position
	Input.action_press("move_down")
	await frames(30)
	Input.action_release("move_down")
	check(player.position.distance_to(start) > 10.0, "player controls remain active during focus")
	print("CAM_FOCUS ",cam.get_screen_center_position()," boss=",mb.position," player=",player.position," offset=",cam.position," left=",player.cam_focus_left," limits=",[cam.limit_left,cam.limit_top,cam.limit_right,cam.limit_bottom])
	check(cam.get_screen_center_position().distance_to(mb.position) < 15.0, "actual viewport centers on boss")
	mb.position += Vector2(30, 10)
	await frames(25)
	check(cam.get_screen_center_position().distance_to(mb.position) < 12.0, "focus follows moving boss")
	await capture("镜头_Boss聚焦")
	var left: float = player.cam_focus_left
	paused = true
	await create_timer(0.2, true).timeout
	check(player.cam_focus_left == left, "paused focus timer freezes")
	paused = false
	await frames(80)
	print("CAM_RETURN ",cam.position," left=",player.cam_focus_left," scale=",Engine.time_scale)
	check(player.cam_focus_left == 0.0 and cam.position.length() < 5.0, "focus smoothly returns to player")
	await frames(40)
	check(cam.position == Vector2.ZERO, "camera return settles exactly")
	await capture("镜头_返回玩家")
	player.focus_camera_on(mb.position, 1.0, mb)
	mb.queue_free()
	await frames(5)
	check(player.cam_focus_left > 0.0, "freed focus target safe")
	player.kill()
	player.start_death()
	await frames(2)
	check(player.cam_focus_left == 0.0 and cam.position == Vector2.ZERO, "death cancels focus")
	var fresh = load("res://scenes/player.tscn").instantiate()
	root.add_child(fresh)
	check(fresh.talent_points == 0 and fresh.talent_health == 0 and not fresh.has_claw, "new scene resets progression")
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	await create_timer(0.15).timeout
	world.queue_free()
	fresh.queue_free()
	await process_frame
	print("PROGRESSION_RESULT ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

