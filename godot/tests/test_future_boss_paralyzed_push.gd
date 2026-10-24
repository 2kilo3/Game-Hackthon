extends SceneTree
## 使用真实角色、Boss 碰撞体与第三段普攻，记录瘫痪中的物理位移。

var checks := 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func _tick(count: int = 1) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _case(direction: Vector2, mode: String) -> void:
	var paralyzed := mode in ["paralyzed", "shielded", "stunned"]
	var arena := Node2D.new()
	root.add_child(arena)
	var player = load("res://scenes/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector2(400, 300) - direction * 52.0
	arena.add_child(player)
	var boss = load("res://scenes/future_boss.tscn").instantiate()
	boss.position = Vector2(400, 300)
	arena.add_child(boss)
	boss.state = "walk"
	boss.shield_up = false
	boss._no_shield_left = 60.0
	boss._shoot_timer = 10.0
	boss.poise = boss.poise_max
	if paralyzed:
		boss._enter_paralyzed()
	if mode == "shielded":
		boss.shield_up = true
	if mode == "stunned":
		boss.stun(1.0)
	if mode == "shooting":
		boss.state = "normal_shoot"
		boss._play("shoot", false)
		boss.sprite.speed_scale = 0.1
	var origin: Vector2 = boss.position
	var player_origin: Vector2 = player.position
	var hp_before: float = boss.hp
	var shield_before: float = boss.shield
	var poise_before: float = boss.poise
	player.facing_dir = direction
	player.facing = player.DIRS[int(round(fposmod(direction.angle(), TAU) / (PI / 4.0))) % 8]
	player.state = "attack"
	player.combo_step = 3
	player._begin_attack_stage()
	var max_shift := 0.0
	var last_frame := 0
	var max_animation_frame := 0
	for i in 40:
		await _tick()
		max_shift = maxf(max_shift, boss.position.distance_to(origin))
		max_animation_frame = maxi(max_animation_frame, boss.sprite.frame)
		last_frame = boss.sprite.frame
	var label := mode + " / " + str(direction)
	samples.append({"direction": str(direction), "mode": mode, "boss_shift": max_shift, "player_shift": player.position.distance_to(player_origin), "damage": hp_before - boss.hp})
	# 原版向下突进追击移动中的 Boss 时，Boss 会先离开命中范围；保留该行为。
	var misses := mode == "walking" and direction == Vector2.DOWN
	var damage: float = 0.0 if mode == "shielded" or misses else player.attack3_damage
	_check(hp_before - boss.hp == damage, "Third strike damage once: " + label)
	_check(player.attack_hit_something == not misses, "Hit/miss result: " + label)
	_check(poise_before - boss.poise == (0.0 if misses else boss.hit_poise_damage), "Poise damage unchanged: " + label)
	_check(shield_before - boss.shield == (boss.shield_damage_cap if mode == "shielded" else 0.0), "Shield absorption unchanged: " + label)
	_check(player.position.distance_to(player_origin) > 1.0, "Player dash preserved: " + str(direction))
	_check(boss.collision_layer == 2 and boss.collision_mask == 1 and not boss.get_node("Collision").disabled, "Collision remains enabled: " + label)
	if paralyzed:
		_check(max_shift < 0.001 and boss.velocity == Vector2.ZERO, "Paralyzed boss stays fixed: " + label)
		_check(boss._paralyzed_left > 0.0, "Paralysis survives hit: " + label)
		if mode != "shielded":
			_check(str(boss.sprite.animation).begins_with("paralyzed_") and last_frame == max_animation_frame and max_animation_frame > 0, "Paralysis animation advances: " + label)
		else:
			_check(str(boss.sprite.animation).begins_with("block_"), "Existing shield hit reaction retained")
	if mode == "paralyzed" and direction == Vector2.RIGHT:
		# 等待真实计时器结束，再在同一个 Boss 身上执行一次完整第三段。
		player.position = origin - Vector2(52, 0)
		player.velocity = Vector2.ZERO
		for i in 240:
			if boss._paralyzed_left <= 0.0:
				break
			await _tick()
		_check(boss._paralyzed_left == 0.0 and boss.state == "walk" and boss.poise == boss.poise_max, "Natural recovery restores walking and poise")
		_check(boss.position.distance_to(origin) < 0.001, "No drift through final paralysis frame")
		var recovered_hp: float = boss.hp
		player.state = "attack"
		player.combo_step = 3
		player._begin_attack_stage()
		await _tick(40)
		_check(boss.position.distance_to(origin) > 1.0, "Movement resumes after recovery")
		_check(recovered_hp - boss.hp == player.attack3_damage, "Third strike hits once after recovery")
		_check(player.position.distance_to(origin - Vector2(52, 0)) > 1.0, "Third strike dash resumes after recovery")
	arena.queue_free()
	await _tick(2)

func _run() -> void:
	var watchdog := Timer.new()
	root.add_child(watchdog)
	watchdog.timeout.connect(func(): quit(2))
	watchdog.start(90.0)
	for direction in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		await _case(direction, "paralyzed")
		await _case(direction, "walking")
		await _case(direction, "shooting")
	for direction in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		await _case(direction.normalized(), "paralyzed")
	for mode in ["shielded", "stunned"]:
		await _case(Vector2.RIGHT, mode)
		await _case(Vector2.DOWN, mode)
	print("PARALYZED_PUSH_RESULT ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "samples": samples}))
	quit(0 if failures.is_empty() else 1)
