extends SceneTree
## 实际玩家输入验证反击应对；实际未来 Boss 验证能量桩生命周期。

var checks := 0
var failures: Array[String] = []
var timings: Array[float] = []

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

func _cleanup(arena: Node) -> void:
	paused = false
	Engine.time_scale = 1.0
	for action in InputMap.get_actions():
		Input.action_release(action)
	for audio in arena.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	arena.queue_free()
	await create_timer(0.1).timeout

func _melee_fixture() -> Dictionary:
	var arena := Node2D.new()
	root.add_child(arena)
	var player: CharacterBody2D = load("res://scenes/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector2(340, 200)
	arena.add_child(player)
	player.facing = "W"
	player.facing_dir = Vector2.LEFT
	var boss: CharacterBody2D = load("res://scenes/modern_boss.tscn").instantiate()
	boss.position = Vector2(300, 200)
	arena.add_child(boss)
	boss.spawned = true
	boss.visible = true
	boss.modulate = Color.WHITE
	boss._decision_left = 100.0
	boss._drag_delay = 100.0
	boss._start_block()
	Input.action_press("attack")
	await _physics()
	Input.action_release("attack")
	for i in 60:
		if boss.state == "counter_windup":
			break
		await _physics()
	_check(boss.blocked_hits == 1 and boss.state == "counter_windup", "Real player attack triggers blocked-hit warning")
	_check(boss.hp == boss.hp_max and player.hp == player.hp_max, "Blocking absorbs the initiating hit without instant counter damage")
	return {"arena": arena, "player": player, "boss": boss}

func _capture(name: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			await RenderingServer.frame_post_draw
			var path := arg.trim_prefix("--capture-dir=").path_join(name)
			_check(root.get_texture().get_image().save_png(path) == OK, "Save warning/assist viewport capture")

func _show_future(boss: CharacterBody2D) -> void:
	# 每个协助攻击用例使用一次全新入场状态。
	boss._entered = false
	boss.dead = false
	boss.begin_entrance()
	boss.set_physics_process(false)
	boss.state = "walk"

func _kill_future(boss: CharacterBody2D) -> void:
	boss.shield_up = false
	boss.shield = 0.0
	boss.state = "walk"
	boss.take_damage(boss.hp + 1.0)

func _run() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.ignore_time_scale = true
	watchdog.timeout.connect(func(): push_error("COMBAT_RULES_TIMEOUT"); quit(1))
	root.add_child(watchdog)
	watchdog.start(50.0)
	root.size = Vector2i(1440, 810)
	var fixture: Dictionary = await _melee_fixture()
	var boss: CharacterBody2D = fixture.boss
	var player: CharacterBody2D = fixture.player
	var started := Time.get_ticks_msec()
	await _physics(25)
	_check(boss.state == "counter_windup" and not boss.sprite.is_playing() and boss.sprite.frame == 0, "Anticipation pose remains visible during the warning")
	_check(player.hp == player.hp_max, "Warning window has no damage")
	await _capture("现代Boss_反击预警.png")
	for i in 120:
		if player.hp < player.hp_max:
			break
		await _physics()
	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
	timings.append(elapsed)
	_check(elapsed >= 0.75 and elapsed < 1.1, "First damage follows at least 0.65s warning plus the strike anticipation")
	_check(player.hp == player.hp_max - boss.counter_damage, "Unanswered counter still deals its original 10 damage")
	await _physics(30)
	_check(player.hp == player.hp_max - boss.counter_damage, "Counter only applies one hit")
	await _cleanup(fixture.arena)

	fixture = await _melee_fixture()
	boss = fixture.boss
	player = fixture.player
	await _physics(30)
	Input.action_press("dodge")
	await _physics(2)
	Input.action_release("dodge")
	_check(player.state == "dodge", "Player can respond with an actual dodge input")
	await _physics(18)
	_check(player.hp == player.hp_max, "Dodging during the warning avoids counter damage")
	_check(player.is_invulnerable() and player.position.distance_to(boss.position) <= boss.combo_range + 26.0, "Dodge immunity covers the actual hit time while still inside the hit radius")
	await _cleanup(fixture.arena)

	fixture = await _melee_fixture()
	boss = fixture.boss
	player = fixture.player
	await _physics(24)
	Input.action_press("block")
	await _physics(2)
	player.perfect_block_used = true
	_check(player.state == "block", "Player can raise a normal guard after the initiating attack")
	for i in 90:
		if player.hp < player.hp_max:
			break
		await _physics()
	_check(player.hp == player.hp_max - boss.counter_damage * player.block_damage_multiplier, "Normal guard applies the existing counter-damage reduction")
	Input.action_release("block")
	await _cleanup(fixture.arena)

	fixture = await _melee_fixture()
	boss = fixture.boss
	player = fixture.player
	await _physics(44)
	Input.action_press("block")
	for i in 20:
		if player.state == "perfect_block":
			break
		await _physics()
	_check(player.state == "perfect_block" and player.hp == player.hp_max, "Timed guard can perfect-block the counter")
	Input.action_release("block")
	await _cleanup(fixture.arena)

	fixture = await _melee_fixture()
	boss = fixture.boss
	player = fixture.player
	for i in 60:
		if boss.state == "counter":
			break
		await _physics()
	var committed_facing: String = boss.facing
	player.position = boss.position - boss.facing_dir() * 40.0
	await _physics(15)
	_check(boss.facing == committed_facing, "Counter direction is committed when the warning ends")
	_check(player.hp == player.hp_max, "Counter cannot hit a player behind the committed direction")
	await _cleanup(fixture.arena)

	fixture = await _melee_fixture()
	boss = fixture.boss
	player = fixture.player
	await _physics(15)
	boss.stun(0.2)
	_check(boss.state == "idle", "Stun cancels the warning instead of leaving a delayed counter")
	await _physics(45)
	_check(player.hp == player.hp_max, "Interrupted warning cannot apply its old counter hit")
	await _cleanup(fixture.arena)

	var arena := Node2D.new()
	root.add_child(arena)
	var pylon: StaticBody2D = load("res://scenes/energy_pylon.tscn").instantiate()
	pylon.position = Vector2(300, 200)
	pylon.attack_interval = 0.1
	arena.add_child(pylon)
	pylon.activated = true
	var modern: CharacterBody2D = load("res://scenes/modern_boss.tscn").instantiate()
	modern.position = pylon.position + Vector2(30, 0)
	arena.add_child(modern)
	modern.visible = true
	modern.modulate = Color.WHITE
	modern.add_to_group("boss")
	modern.set_physics_process(false)
	var future: CharacterBody2D = load("res://scenes/future_boss.tscn").instantiate()
	future.position = pylon.position + Vector2(100, 0)
	arena.add_child(future)
	future.visible = false
	future.process_mode = Node.PROCESS_MODE_DISABLED
	pylon._try_attack()
	await _physics(45)
	_check(pylon.attacks_made == 0 and not pylon._attacking and pylon._find_boss() == null, "No assistance before FutureBoss appears")
	_check(modern.hp == modern.hp_max, "A closer modern boss is never an assist target")
	future.visible = true
	pylon._try_attack()
	_check(not pylon._attacking, "Visible but disabled pre-spawn FutureBoss is not an assist target")
	_show_future(future)
	pylon.activated = false
	pylon._try_attack()
	_check(not pylon._attacking, "Unpowered pylons remain inactive even after FutureBoss appears")
	pylon.activated = true
	var shield_before: float = future.shield
	pylon._try_attack()
	_check(pylon._attacking and pylon._attack_target == future, "Appeared living FutureBoss enables assistance")
	await _physics(14)
	_check(pylon.attacks_made == 1 and future.shield == shield_before - pylon.attack_damage, "Assist deals one normal laser hit to FutureBoss")
	_check(pylon._laser_left > 0.0 and modern.hp == modern.hp_max, "Laser feedback remains visible and other bosses remain unharmed")
	await _physics(14)
	_check(not pylon._attacking and pylon._laser_left > 0.0, "Completed shot keeps its short visual beam while the boss is alive")
	_kill_future(future)
	_check(pylon._laser_left == 0.0 and pylon._laser_target == Vector2.ZERO and pylon._attack_target == null, "External killing hit immediately clears an already visible beam and lock")
	_show_future(future)
	var count_before: int = pylon.attacks_made
	pylon._try_attack()
	await _physics(5)
	_kill_future(future)
	_check(not pylon._attacking and pylon._attack_target == null and pylon._laser_left == 0.0, "Death immediately cancels a pending attack, beam and target lock")
	await _physics(70)
	_check(is_instance_valid(future) and future.dead and pylon.attacks_made == count_before, "Existing corpse never receives a delayed or repeated attack")
	_check(pylon._find_boss() == null, "Corpse is excluded from target selection")

	_show_future(future)
	future.shield_up = false
	future.shield = 0.0
	future.hp = pylon.attack_damage
	count_before = pylon.attacks_made
	pylon._try_attack()
	await _physics(16)
	_check(future.dead and pylon.attacks_made == count_before + 1, "A lethal assist hit is counted exactly once")
	_check(pylon._attack_target == null and not pylon._attacking and pylon._laser_left == 0.0 and pylon._laser_target == Vector2.ZERO, "Lethal hit immediately clears its own beam and corpse lock")
	await _physics(45)
	_check(pylon.attacks_made == count_before + 1, "No further attacks follow a lethal assist")

	_show_future(future)
	var second: StaticBody2D = load("res://scenes/energy_pylon.tscn").instantiate()
	second.position = pylon.position + Vector2(0, 40)
	arena.add_child(second)
	second.activated = true
	second.attack_interval = 0.1
	future.shield_up = false
	future.shield = 0.0
	future.hp = pylon.attack_damage
	count_before = pylon.attacks_made + second.attacks_made
	pylon._try_attack()
	second._try_attack()
	await _physics(20)
	_check(future.dead and pylon.attacks_made + second.attacks_made == count_before + 1, "Two pylons do not duplicate a killing hit")
	_check(pylon._attack_target == null and second._attack_target == null and not second._attacking, "Boss death synchronously clears every pylon")

	_show_future(future)
	second.activated = false
	pylon._try_attack()
	await _physics(4)
	count_before = pylon.attacks_made
	future.hide()
	await _physics(30)
	_check(pylon.attacks_made == count_before and pylon._attack_target == null, "A target hidden during windup cannot receive the hit")
	_show_future(future)
	pylon._try_attack()
	await _physics(4)
	count_before = pylon.attacks_made
	future.queue_free()
	await _physics(30)
	_check(pylon.attacks_made == count_before and pylon._attack_target == null and not pylon._attacking, "Removed targets cancel safely without stale callbacks")
	await _cleanup(arena)
	watchdog.queue_free()
	await process_frame
	print("COMBAT_RULES_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "counter_hit_seconds": timings, "passed": failures.is_empty()}))
	quit.call_deferred(0 if failures.is_empty() else 1)
