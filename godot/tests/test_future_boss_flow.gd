extends SceneTree

var checks := 0
var failures: Array[String] = []
var completed := 0
var handoff := {}
var seen_frames := {}

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

func capture(label: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(label + ".png")) == OK, "save " + label)

func _run() -> void:
	create_timer(50.0, true, false, true).timeout.connect(func(): push_error("BOSS_FLOW_TIMEOUT"); quit(2))
	var timeline = root.get_node("Timeline")
	timeline.reset()
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	# 此测试隔离战斗/界面时钟；事件剧情由 test_story.gd 覆盖。
	world.get_node("DialogueHost").set_process(false)
	current_scene = world
	await frames(2)
	world.set_process(false)
	var player = world.player
	var boss = world.get_node("YSort/FutureBoss")
	var modern = world.get_node("YSort/ModernBoss")
	check(not boss.visible and boss.process_mode == Node.PROCESS_MODE_DISABLED and boss.collision_layer == 0, "dormant future boss inactive in Modern")
	boss.begin_entrance()
	check(not boss._entered and not boss.visible, "future boss direct entrance cannot bypass era ownership")
	check(not modern.visible and modern.collision_layer == 0, "modern boss dormant before normal enemies defeated")
	for enemy in world._entities_modern + world._entities_future:
		enemy.dead = true
	world._start_future_boss_transform()
	check(not world._boss_transform_running, "direct transformation request in Modern rejected")
	timeline.set_era(1)
	await frames(2)
	check(not boss.visible and boss.collision_layer == 0, "visiting Future alone does not activate boss")
	check(not world.is_boss_entrance_ready(), "dead fixture alone does not bypass modern boss defeat flag")
	world.modern_boss_defeated = true
	check(world.is_boss_entrance_ready(), "normal cleared progression ready in Future")
	world._check_boss_entrance()
	var actor = world._boss_transform_actor
	check(is_instance_valid(actor) and world._boss_transform_running and world.boss_entered, "official trigger starts exactly one cinematic actor")
	check(actor.phase == "enter" and actor.sprite.sprite_frames == load("res://resources/boss_modern_frames.tres"), "modern form appears first")
	check(not actor.has_method("take_damage") and not actor.has_method("stun") and not actor is CollisionObject2D, "cinematic is not a combat/reward target")
	check(not boss.visible and not boss._entered, "future form not active during modern entrance")
	world._check_boss_entrance()
	world._start_future_boss_transform()
	check(world._boss_transform_actor == actor, "repeated triggers do not restart cinematic")
	actor.finished.connect(func():
		completed += 1
		handoff = {"actor": actor.global_position, "boss": boss.global_position, "visible": boss.visible, "entered": boss._entered, "last_frame": actor.sprite.frame}
	)
	actor.sprite.frame_changed.connect(func():
		if actor.phase == "transform" and actor.sprite.animation == &"transform":
			seen_frames[actor.sprite.frame] = true
	)
	await frames(30)
	check(actor.phase == "enter" and actor.modulate.a > 0.2 and actor.modulate.a < 0.8, "normal entrance walks and fades in")
	check(actor.position.distance_to(Vector2(300, -150)) > 15.0, "modern form moves during entrance")
	await capture("01_现代形态正常出场")
	timeline.set_era(0)
	await frames(2)
	var walk_left: float = actor.entrance_left
	var walk_pos: Vector2 = actor.position
	var walk_frame: int = actor.sprite.frame
	check(not actor.visible and actor.process_mode == Node.PROCESS_MODE_DISABLED, "cinematic hidden and disabled in Modern")
	Input.action_press("move_down")
	var player_pos: Vector2 = player.position
	await frames(20)
	Input.action_release("move_down")
	check(player.position.distance_to(player_pos) > 5.0, "player still moves normally after switching")
	await frames(190)
	check(actor.entrance_left == walk_left and actor.position == walk_pos and actor.sprite.frame == walk_frame, "off-era entrance clock, animation and position freeze")
	check(not boss.visible and not boss._entered and completed == 0, "no delayed callback activates boss in Modern")
	check(not modern.visible, "defeated modern boss not revived by switching")
	await capture("02_现代时空无未来Boss")
	timeline.set_era(1)
	check(world._boss_transform_actor == actor and actor.visible, "return resumes same actor")
	check(player.cam_focus_target == actor and player.cam_focus_left > 0.0, "return restores cinematic focus")
	for i in 120:
		if actor.phase == "transform":
			break
		await frames()
	check(actor.phase == "transform" and actor.modulate.a == 1.0, "modern entrance completes before transformation")
	check(actor.sprite.animation == &"transform" and actor.sprite.sprite_frames == load("res://resources/transform_frames.tres"), "real transformation frames start")
	check(not boss.visible and not boss._entered, "future form waits for all transformation frames")
	await frames(38)
	await capture("03_变身动画中段")
	timeline.set_era(0)
	await frames(2)
	var transform_frame: int = actor.sprite.frame
	var transform_progress: float = actor.sprite.frame_progress
	await frames(130)
	check(actor.sprite.frame == transform_frame and is_equal_approx(actor.sprite.frame_progress, transform_progress), "off-era transformation freezes exact frame")
	check(not boss.visible and completed == 0, "transformation cannot complete in Modern")
	timeline.set_era(1)
	for i in 180:
		if completed > 0:
			break
		await frames()
	check(completed == 1 and not world._boss_transform_running, "single handoff after transformation")
	check(handoff.get("last_frame", -1) == 23 and seen_frames.size() == 24, "all 24 transform frames played before handoff")
	check(handoff.get("actor", Vector2.ZERO).distance_to(handoff.get("boss", Vector2.INF)) < 0.001, "handoff preserves exact world position")
	check(handoff.get("visible", false) and handoff.get("entered", false), "future boss becomes active only at handoff")
	await frames(2)
	check(not is_instance_valid(actor) and world._boss_transform_actor == null, "cinematic actor removed after handoff")
	check(boss.state == "enter" and String(boss.sprite.animation).begins_with("charge_"), "future form enters with correct charge animation")
	check(boss.collision_layer == 2 and boss.collision_mask == 1, "future boss restores original collision layers")
	await capture("04_未来形态接续入场")
	boss.hp = 73.0
	boss.shield = 27.0
	boss.poise = 13.0
	boss.shield_up = false
	boss._no_shield_left = 12.0
	boss._paralyzed_left = 2.0
	boss.state = "paralyzed"
	boss._play("paralyzed", false)
	boss._shots_left = 3
	boss._shot_gap = 0.15
	boss.position = Vector2(250, -80)
	var hook = load("res://scenes/claw_hook.tscn").instantiate()
	hook.target = boss
	hook.owner_actor = player
	world.ysort.add_child(hook)
	hook.position = player.position
	boss._fire(player)
	check(get_nodes_in_group("era_projectile").size() >= 2, "fixture creates live boss bullet and player hook")
	timeline.set_era(0)
	var old_boss_position: Vector2 = boss.position
	hook._hit_target()
	check(boss.position == old_boss_position, "pending hook cannot pull disabled boss into Modern")
	await frames(2)
	check(get_nodes_in_group("era_projectile").is_empty(), "old-era boss projectiles and hooks are removed")
	var snapshot := [boss.position, boss.hp, boss.shield, boss.poise, boss._no_shield_left, boss._paralyzed_left, boss._shots_left, boss._shot_gap]
	Input.action_press("move_left")
	await frames(30)
	Input.action_release("move_left")
	check(snapshot == [boss.position, boss.hp, boss.shield, boss.poise, boss._no_shield_left, boss._paralyzed_left, boss._shots_left, boss._shot_gap], "boss combat state completely retained off-era")
	check(not boss.visible and boss.collision_layer == 0 and boss.collision_mask == 0, "combat boss hidden and noncolliding in Modern")
	check(boss.get_parent() == world.ysort and boss.get_parent() != player, "boss remains world entity, never reparented to player")
	timeline.set_era(1)
	check(boss.visible and boss.hp == 73 and boss.shield == 27 and boss.poise == 13 and boss.state == "paralyzed", "return retains damage and state without respawn")
	await frames(6)
	check(boss._paralyzed_left < float(snapshot[5]), "combat timers resume only in Future")
	boss.begin_entrance()
	world._check_boss_entrance()
	world._start_future_boss_transform()
	check(boss.hp == 73 and boss.shield == 27 and boss.state == "paralyzed" and completed == 1, "duplicate begin cannot heal or replay entrance")
	for i in 5:
		timeline.set_era(0)
		await frames(2)
		check(not boss.visible and boss.process_mode == Node.PROCESS_MODE_DISABLED, "repeat switch to Modern " + str(i))
		timeline.set_era(1)
		await frames(2)
		check(boss.visible and boss.hp == 73 and boss.collision_layer == 2, "repeat switch to Future " + str(i))
	world.set_process(true)
	Input.action_press("switch_time")
	await frames(2)
	Input.action_release("switch_time")
	check(player.is_era_shifting(), "real R action starts player transition")
	for i in 120:
		if not timeline.is_future():
			break
		await frames()
	check(not timeline.is_future() and not boss.visible, "real transition midpoint disables future boss")
	var real_switch_pos: Vector2 = boss.position
	await frames(90)
	check(boss.position == real_switch_pos and boss.hp == 73, "boss remains fixed during full player transition")
	Input.action_press("switch_time")
	await frames(2)
	Input.action_release("switch_time")
	for i in 120:
		if timeline.is_future():
			break
		await frames()
	check(timeline.is_future() and boss.visible and boss.hp == 73, "real R return resumes same boss state")
	world.set_process(false)
	var points: int = player.talent_points
	boss._die()
	check(player.talent_points == points + 2, "real boss death still grants two talent points")
	timeline.set_era(0)
	await frames(2)
	var corpse_time: float = boss.dead_left
	await frames(10)
	check(boss.dead and boss.dead_left == corpse_time and not boss.visible, "dead future boss stays off-era")
	timeline.set_era(1)
	boss.begin_entrance()
	world._check_boss_entrance()
	check(boss.dead and player.talent_points == points + 2 and completed == 1, "dead boss cannot respawn or award again")
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	await create_timer(0.15).timeout
	world.queue_free()
	await process_frame
	print("FUTURE_BOSS_FLOW_RESULT ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures, "transform_frames": seen_frames.size(), "handoffs": completed}))
	quit(0 if failures.is_empty() else 1)
