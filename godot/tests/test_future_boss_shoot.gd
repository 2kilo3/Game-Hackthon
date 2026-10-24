extends SceneTree
## 使用真实 Boss 场景、物理帧与动画时钟，验证破盾后的普通射击。

var checks := 0
var failures: Array[String] = []
var shot_samples: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _physics(count: int = 1) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _wait_for_shot(boss: CharacterBody2D, max_frames: int = 360) -> void:
	for i in max_frames:
		if boss.state == "normal_shoot":
			return
		await _physics()
	_check(false, "Normal shot starts before timeout")

func _sample_shot(boss: CharacterBody2D, label: String) -> void:
	var origin := boss.position
	var animation: StringName = boss.sprite.animation
	var start_frame: int = boss.sprite.frame
	var max_frame := start_frame
	var previous_frame := start_frame
	var max_displacement := 0.0
	var max_speed := 0.0
	var stable_animation := true
	var forward_frames := true
	var frames := 0
	while boss.state == "normal_shoot" and frames < 90:
		max_displacement = maxf(max_displacement, boss.position.distance_to(origin))
		max_speed = maxf(max_speed, boss.velocity.length())
		stable_animation = stable_animation and boss.sprite.animation == animation
		forward_frames = forward_frames and boss.sprite.frame >= previous_frame
		previous_frame = boss.sprite.frame
		max_frame = maxi(max_frame, boss.sprite.frame)
		frames += 1
		await _physics()
	_check(frames > 0 and frames < 90, label + ": shot completes")
	_check(stable_animation and forward_frames and max_frame > start_frame, label + ": shooting frames advance without being replaced or restarted")
	_check(max_frame == boss.sprite.sprite_frames.get_frame_count(animation) - 1, label + ": final shooting frame is displayed")
	_check(max_displacement < 0.001 and max_speed < 0.001, label + ": stays stationary for the whole shot")
	shot_samples.append({"label": label, "animation": animation, "max_frame": max_frame, "physics_samples": frames, "max_displacement": max_displacement, "max_speed": max_speed})

func _capture() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			var path := arg.trim_prefix("--capture-dir=").path_join("未来Boss_破盾后普通射击.png")
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png(path) == OK, "Capture ordinary shooting in the real World")

func _run() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.ignore_time_scale = true
	watchdog.timeout.connect(func(): push_error("FUTURE_BOSS_SHOOT_TIMEOUT"); quit(1))
	root.add_child(watchdog)
	watchdog.start(45.0)
	var arena := Node2D.new()
	root.add_child(arena)
	var target := Node2D.new()
	target.name = "Player"
	target.position = Vector2(600, 220)
	arena.add_child(target)
	var boss: CharacterBody2D = load("res://scenes/future_boss.tscn").instantiate()
	boss.position = Vector2(300, 220)
	boss.set_physics_process(false)
	arena.add_child(boss)
	boss.state = "walk"
	boss.shield = 10.0
	boss.velocity = Vector2(90, 25)
	boss.take_damage(9.0)
	_check(boss.shield == 1.0 and boss.shield_up and boss.shield_breaks == 0, "Positive shield does not trigger the broken-shield behavior")
	boss._shoot_timer = 9.0
	boss._shots_left = 4
	boss.take_damage(1.0)
	_check(boss.shield == 0.0 and not boss.shield_up and boss.shield_breaks == 1, "Exactly zero shield triggers shield break once")
	_check(boss.state == "paralyzed" and boss._paralyzed_left == boss.break_seconds, "Original shield-break paralysis is preserved")
	_check(boss.velocity == Vector2.ZERO and boss._shots_left == 0 and boss._block_left == 0.0, "Shield break stops movement and cancels the old shielded attack")
	_check(boss._shoot_timer == 0.0, "Old shot cooldown cannot delay the first unshielded shot")
	var shots_before: int = boss.volleys_fired
	boss.set_physics_process(true)
	await _physics(30)
	_check(boss._paralyzed_left > 0.0 and boss.volleys_fired == shots_before, "No shooting during shield-break paralysis")
	await _wait_for_shot(boss)
	_check(boss.sprite.animation == &"shoot_E" and boss.volleys_fired == shots_before + 1, "Recovery starts one ordinary shot with the corresponding animation")
	_check(not boss.sprite.sprite_frames.get_animation_loop(boss.sprite.animation), "Ordinary shot animation is not looping")
	var bullets: Array[Node] = arena.get_children().filter(func(node): return node.has_method("is_bullet"))
	_check(bullets.size() == 1 and bullets[0].direction.is_equal_approx(Vector2.RIGHT), "Shot creates a real projectile aimed at the player")
	await _sample_shot(boss, "First shot after shield break")
	var after_shot := boss.position
	await _physics(6)
	_check(boss.state == "walk" and boss.position.distance_to(after_shot) > 0.1, "Normal walking resumes between shots")
	await _wait_for_shot(boss, 120)
	_check(boss.volleys_fired == shots_before + 2, "Unshielded phase fires repeated single shots")
	await _sample_shot(boss, "Repeated shot")

	for direction in boss.DIRS:
		boss.set_physics_process(false)
		boss.state = "walk"
		boss.shield_up = false
		boss._no_shield_left = 30.0
		boss._shoot_timer = 0.0
		target.position = boss.position + boss._dir_vector(direction) * 300.0
		shots_before = boss.volleys_fired
		boss.set_physics_process(true)
		await _wait_for_shot(boss, 10)
		_check(boss.sprite.animation == StringName("shoot_" + direction), "Correct ordinary shooting animation: " + direction)
		_check(boss.volleys_fired == shots_before + 1, "One projectile per ordinary shot: " + direction)
		await _sample_shot(boss, direction)

	boss._shoot_timer = 0.0
	await _wait_for_shot(boss, 10)
	shots_before = boss.volleys_fired
	boss.stun(0.1)
	_check(boss.stun_left > 0.0 and boss.velocity == Vector2.ZERO, "Stun interrupts an ordinary shot and stops movement")
	await _physics(10)
	_check(boss.stun_left == 0.0 and boss.state == "walk", "After stun, the old shooting state cannot lock the boss")
	_check(boss.volleys_fired == shots_before, "Stun does not create an extra projectile")

	boss.set_physics_process(false)
	boss.state = "walk"
	boss.shield_up = true
	boss.shield = 2.0
	boss.poise = boss.poise_max
	var breaks_before: int = boss.shield_breaks
	boss.take_laser_damage(2.0)
	_check(not boss.shield_up and boss.shield_breaks == breaks_before + 1, "Energy-pylon laser can also trigger shield break")
	_check(boss.poise == boss.poise_max, "Laser damage still does not reduce poise")
	boss._paralyzed_left = 0.05
	boss.set_physics_process(true)
	await _wait_for_shot(boss, 20)
	_check(String(boss.sprite.animation).begins_with("shoot_"), "Laser shield break also starts ordinary shooting after recovery")
	boss._no_shield_left = 0.03
	await _physics(4)
	_check(boss.shield_up and boss.shield == boss.shield_recover_amount, "Shield still recovers to the original amount")
	_check(boss.state == "normal_shoot" and String(boss.sprite.animation).begins_with("shoot_"), "Shield recovery does not cut off the active ordinary shot")
	await _sample_shot(boss, "Shield recovery during shot")
	_check(String(boss.sprite.animation).begins_with("shield_walk_"), "Shielded locomotion resumes after the shot completes")

	boss.set_physics_process(false)
	boss.state = "walk"
	boss._block_left = 0.0
	shots_before = boss.volleys_fired
	boss._start_volley(target)
	boss.set_physics_process(true)
	var volley_origin := boss.position
	var volley_displacement := 0.0
	for i in 90:
		if boss._shots_left <= 0:
			break
		volley_displacement = maxf(volley_displacement, boss.position.distance_to(volley_origin))
		await _physics()
	_check(boss.volleys_fired == shots_before + boss.volley_count, "Original shielded five-shot volley is preserved")
	_check(volley_displacement < 0.001, "Original shielded volley also remains stationary")
	boss.set_physics_process(false)
	boss.state = "walk"
	boss.shield_up = false
	boss._no_shield_left = 30.0
	boss._shoot_timer = 0.0
	target.name = "AbsentPlayer"
	shots_before = boss.volleys_fired
	boss.set_physics_process(true)
	await _physics(10)
	_check(boss.volleys_fired == shots_before and boss.state != "normal_shoot", "Missing player does not create an invalid shot")
	for audio in arena.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	arena.queue_free()
	await process_frame

	var world: Node2D = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	# 此测试隔离战斗/界面时钟；事件剧情由 test_story.gd 覆盖。
	world.get_node("DialogueHost").set_process(false)
	current_scene = world
	root.size = Vector2i(1440, 810)
	root.get_node("Timeline").set_era(1)
	world.set_process(false)
	for actor in world.ysort.get_children():
		if actor.name != "FutureBoss":
			actor.process_mode = Node.PROCESS_MODE_DISABLED
	var live_boss: CharacterBody2D = world.get_node("YSort/FutureBoss")
	live_boss.begin_entrance()
	live_boss.state = "walk"
	live_boss.position = world.player.position + Vector2(180, 0)
	live_boss.take_laser_damage(live_boss.shield_max)
	live_boss._paralyzed_left = 0.05
	await _wait_for_shot(live_boss, 30)
	_check(live_boss.sprite.animation == &"shoot_W" and not live_boss.shield_up, "Real World switches to the unshielded shooting animation")
	_check(world.get_node("HUD/BossHud")._find_boss() == live_boss, "Boss HUD still resolves the real World boss")
	await _physics(7)
	await _capture()
	await _sample_shot(live_boss, "Real World")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	world.queue_free()
	current_scene = null
	watchdog.queue_free()
	await create_timer(0.1).timeout
	await process_frame
	print("FUTURE_BOSS_SHOOT_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "shots": shot_samples, "passed": failures.is_empty()}))
	quit.call_deferred(0 if failures.is_empty() else 1)
