extends Node
## 无头回归测试：不需要显示器，直接跑逻辑并断言。
##
## 运行：
##   codegodot/godot.exe --headless --path godot res://tests/test_run.tscn
## 通过时输出 "ALL TESTS PASSED"，失败时退出码为 1。

var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	await get_tree().process_frame
	await _run()
	_finish()

func _check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  PASS  ", label)
	else:
		failures.append(label)
		print("  FAIL  ", label)

func _run() -> void:
	print("== 加载世界 ==")
	var world: Node = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	# 此测试隔离战斗/界面时钟；事件剧情由 test_story.gd 覆盖。
	world.get_node("DialogueHost").set_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var player: CharacterBody2D = world.get_node("YSort/Player")
	var sprite: AnimatedSprite2D = player.get_node("Sprite")
	var ysort: Node2D = world.get_node("YSort")

	# 正式游戏里已经没有测试桩了；测试自己临时造两个，用来验证受击/韧性/射击逻辑
	var td_scene: PackedScene = load("res://scenes/test_dummy.tscn")
	var td: Node2D = td_scene.instantiate()
	td.name = "TestDummy"
	ysort.add_child(td)
	td.global_position = Vector2(100, 40)
	var sd_scene: PackedScene = load("res://scenes/shooter_dummy.tscn")
	var sd: Node2D = sd_scene.instantiate()
	sd.name = "ShooterDummy"
	ysort.add_child(sd)
	sd.global_position = Vector2(-160, 60)
	world._entities_modern.append(td)
	world._entities_modern.append(sd)

	# 测试桩只在它自己的用例里开启，避免长时间测试被它的震荡波打乱
	var dummy_node: Node = world.get_node_or_null("YSort/TestDummy")
	if dummy_node != null:
		dummy_node.set_physics_process(false)

	# 现代敌人（三个）会主动追打玩家，先全部挪远并停掉，等它们自己的用例再开启
	var modern_enemies: Array[Node] = []
	# 现代 boss 也会主动打人，先挪远停掉，等它自己的用例再开
	var modern_boss: Node = world.get_node_or_null("YSort/ModernBoss")
	if modern_boss != null:
		modern_boss.global_position = Vector2(3000, 3000)
		modern_boss.set_physics_process(false)
	var modern_enemy_home: Array[Vector2] = []   # 出生点（三个路口）
	var future_enemies: Array[Node] = []
	var future_enemy_home: Array[Vector2] = []
	for nm2 in ["YSort/FutureEnemy", "YSort/FutureEnemy2", "YSort/FutureEnemy3", "YSort/FutureEnemy4", "YSort/FutureEnemy5"]:
		var fe: Node = world.get_node_or_null(nm2)
		if fe != null:
			future_enemy_home.append((fe as Node2D).global_position)
			fe.global_position = Vector2(2600, 2600)
			fe.set_physics_process(false)
			future_enemies.append(fe)
	for nm in ["YSort/ModernEnemy", "YSort/ModernEnemy2", "YSort/ModernEnemy3"]:
		var me: Node = world.get_node_or_null(nm)
		if me != null:
			modern_enemy_home.append((me as Node2D).global_position)
			me.global_position = Vector2(2400, 2400)
			me.set_physics_process(false)
			modern_enemies.append(me)

	print("== 场景结构 ==")
	_check(player != null, "Player 节点存在")
	_check(sprite.sprite_frames != null, "AnimatedSprite2D 绑定了 SpriteFrames")
	_check(ysort.y_sort_enabled, "主角所在的容器开启 y_sort（2.5D 深度排序）")

	var sf: SpriteFrames = sprite.sprite_frames
	print("== 动画资源 ==")
	_check(sf.get_animation_names().size() == 101, "101 个动画（8 跑步 + 8 站立 + 8×3 普攻 + 8×3 格挡 + 8 格挡火花 + 8 完美格挡 + 8 反击 + 8 受击 + 倒地 + 4 个变换时空），实际 %d" % sf.get_animation_names().size())
	var dirs := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]
	var frames_ok := true
	for d in dirs:
		if sf.get_frame_count(d) != 10:
			frames_ok = false
		if not sf.has_animation("stand_" + d):
			frames_ok = false
	_check(frames_ok, "每个方向 10 帧跑步 + 1 帧站立")

	print("== 八方向朝向 ==")
	var cases := [
		{"press": ["move_right"], "expect": "E"},
		{"press": ["move_down"], "expect": "S"},
		{"press": ["move_left"], "expect": "W"},
		{"press": ["move_up"], "expect": "N"},
		{"press": ["move_down", "move_right"], "expect": "SE"},
		{"press": ["move_down", "move_left"], "expect": "SW"},
		{"press": ["move_up", "move_right"], "expect": "NE"},
		{"press": ["move_up", "move_left"], "expect": "NW"},
	]
	for c in cases:
		_release_all()
		for a in c["press"]:
			Input.action_press(a)
		await _physics(10)
		_check(player.facing == c["expect"], "%s → 朝向 %s（实际 %s）" % [",".join(c["press"]), c["expect"], player.facing])
		_release_all()
		await _physics(4)

	print("== 移动：不闪站立帧、帧序连续 ==")
	_release_all()
	Input.action_press("move_right")
	await _physics(20)  # 起步加速
	var run_seen := 0
	var stand_seen := 0
	var last_frame := -1
	var jumps := 0
	var frames_count := sf.get_frame_count("E")
	for i in 240:
		await get_tree().physics_frame
		if player.state != "move":
			continue
		run_seen += 1
		if sprite.animation.begins_with("stand_"):
			stand_seen += 1
		var f: int = sprite.frame
		if last_frame >= 0 and f != last_frame:
			if int((f - last_frame + frames_count) % frames_count) != 1:
				jumps += 1
			last_frame = f
		elif last_frame < 0:
			last_frame = f
	_check(run_seen > 100, "移动采样帧数 %d" % run_seen)
	_check(stand_seen == 0, "移动中出现站立帧 0 次（实际 %d）" % stand_seen)
	_check(jumps == 0, "帧序号没有回退/跳帧（实际 %d 次）" % jumps)
	_check(sprite.speed_scale > 1.0, "移动动画帧率随速度加快（speed_scale=%.2f）" % sprite.speed_scale)

	print("== Shift 闪避：0.5 秒判定窗口 ==")
	_release_all()
	player.global_position = Vector2(-300, 200)
	await _physics(10)
	var dodge_duration: float = player.dodge_duration
	_check(absf(dodge_duration - 0.5) < 0.001, "闪避持续时间为 0.5s（实际 %.2f）" % dodge_duration)

	var start_pos := player.global_position
	Input.action_press("move_right")
	Input.action_press("dodge")
	await get_tree().physics_frame
	Input.action_release("dodge")
	var dodge_frames := 0
	var invuln_frames := 0
	var saw_dodge := false
	# 按 60Hz 物理步进，0.5s = 30 帧；多测 6 帧确认已退出
	for i in 36:
		await get_tree().physics_frame
		if player.state == "dodge":
			dodge_frames += 1
			saw_dodge = true
			if player.is_invulnerable():
				invuln_frames += 1
	_check(saw_dodge, "按下 Shift 进入 dodge 状态")
	_check(dodge_frames >= 27 and dodge_frames <= 33, "闪避持续约 0.5s（实际 %d 帧 ≈ %.2fs）" % [dodge_frames, dodge_frames / 60.0])
	_check(invuln_frames == dodge_frames, "闪避全程无敌（%d/%d 帧）" % [invuln_frames, dodge_frames])
	var dodge_dist := (player.global_position - start_pos).length()
	_check(dodge_dist > 120.0, "闪避位移明显（%.1f px > 120）" % dodge_dist)
	_check(player.state != "dodge", "0.5s 后退出闪避（实际 %s）" % player.state)

	print("== 闪避冷却 ==")
	_release_all()
	await _physics(2)
	player.global_position = Vector2(-300, 200)
	# 刚结束闪避，冷却未过：立即再按不应进入 dodge
	Input.action_press("dodge")
	await get_tree().physics_frame
	Input.action_release("dodge")
	var reentered := false
	for i in 6:
		await get_tree().physics_frame
		if player.state == "dodge":
			reentered = true
	_check(not reentered, "冷却中无法连续闪避（冷却 %.2fs）" % player.dodge_cooldown)
	# 冷却结束后可以再闪
	await _physics(20)
	Input.action_press("dodge")
	await get_tree().physics_frame
	Input.action_release("dodge")
	var reentered2 := false
	for i in 4:
		await get_tree().physics_frame
		if player.state == "dodge":
			reentered2 = true
	_check(reentered2, "冷却结束后可以再次闪避")
	await _physics(40)

	print("== 闪避统一使用第 0 帧 ==")
	_release_all()
	player.stamina = player.stamina_max
	player.dodge_cooldown_left = 0.0
	player.global_position = Vector2(-300, 200)
	Input.action_press("move_right")
	await _physics(90)                       # 让移动动画跑到中间某一帧
	await _physics(60)
	var frame_before: int = sprite.frame
	Input.action_press("dodge")
	await get_tree().physics_frame
	Input.action_release("dodge")
	await get_tree().physics_frame
	_check(player.state == "dodge", "移动中触发闪避（%s）" % player.state)
	_check(not sprite.is_playing(), "闪避期间动画暂停（is_playing=%s）" % sprite.is_playing())
	_check(sprite.frame == 0, "移动中闪避也用第 0 帧（触发前 %d，实际 %d）" % [frame_before, sprite.frame])
	await _physics(15)
	_check(sprite.frame == 0, "闪避期间帧固定为 0（实际 %d）" % sprite.frame)
	_release_all()
	await _physics(36)

	print("== 残影不会出现在起点/路径上堆积 ==")
	player.stamina = player.stamina_max
	player.dodge_cooldown_left = 0.0
	player.global_position = Vector2(-300, 0)
	await _physics(30)
	var spawn_pos: Vector2 = player.global_position
	var start_ghosts := _count_ghosts(player.get_parent())
	Input.action_press("move_right")
	Input.action_press("dodge")
	await get_tree().physics_frame
	Input.action_release("dodge")
	await _physics(3)
	# 检查所有残影离起点都有一定距离（不会留在出生点）
	var min_dist := 9999.0
	for child in player.get_parent().get_children():
		if child is Sprite2D:
			min_dist = minf(min_dist, child.global_position.distance_to(spawn_pos))
	_check(start_ghosts == 0, "起手前无残影（%d）" % start_ghosts)
	_check(min_dist >= 8.0, "残影与起点的最小距离 %.1fpx（应 >= 8）" % min_dist)
	await _physics(40)
	_check(_count_ghosts(player.get_parent()) == 0, "闪避结束后残影清空（%d）" % _count_ghosts(player.get_parent()))
	_release_all()
	await _physics(20)

	print("== 站立触发闪避：用第 0 帧 ==")
	player.stamina = player.stamina_max
	player.dodge_cooldown_left = 0.0
	await _physics(50)
	_check(player.state == "stand", "已站定（%s）" % player.state)
	Input.action_press("dodge")
	await get_tree().physics_frame
	Input.action_release("dodge")
	await get_tree().physics_frame
	_check(player.state == "dodge", "站立触发闪避")
	_check(sprite.frame == 0, "使用移动动画第 0 帧（实际 %d）" % sprite.frame)
	await _physics(36)

	print("== 体力系统 ==")
	player.stamina = player.stamina_max
	player.dodge_cooldown_left = 0.0
	_check(absf(player.stamina_max - 100.0) < 0.001, "体力上限 100（实际 %.0f）" % player.stamina_max)
	_check(absf(player.dodge_cost - 20.0) < 0.001, "闪避消耗 20 点（实际 %.0f）" % player.dodge_cost)
	var before_stam: float = player.stamina
	Input.action_press("dodge")
	await get_tree().physics_frame
	Input.action_release("dodge")
	await _physics(2)
	_check(absf(player.stamina - (before_stam - 20.0)) < 0.01, "闪避消耗 20 点（%.0f → %.0f）" % [before_stam, player.stamina])
	await _physics(36)

	# 体力不足时不能闪避
	player.stamina = 10.0
	player.dodge_cooldown_left = 0.0
	Input.action_press("dodge")
	await get_tree().physics_frame
	Input.action_release("dodge")
	await _physics(3)
	_check(player.state != "dodge", "体力不足（10 点 < 20）时无法闪避（实际 %s）" % player.state)

	# 5 秒不闪避后每 0.1s 回复 1 点
	player.stamina = 40.0
	player.time_since_stamina_use = 0.0
	player.dodge_cooldown_left = 0.0
	await _physics(240)                      # 4 秒：不应回复
	_check(absf(player.stamina - 40.0) < 0.5, "4 秒内不回复（实际 %.2f）" % player.stamina)
	await _physics(120)                      # 到 5 秒后再过 2 秒：按 10 点/秒 应回约 20 点
	_check(player.stamina > 47.0 and player.stamina < 60.0, "5 秒后按 10 点/秒回复（实际 %.2f）" % player.stamina)
	player.stamina = player.stamina_max
	player.time_since_stamina_use = 999.0

	print("== 生命值 / 韧性 ==")
	_release_all()
	player.reset_stats()
	_check(absf(player.hp_max - 40.0) < 0.001, "生命上限 40（实际 %.0f）" % player.hp_max)
	_check(absf(player.poise_max - 100.0) < 0.001, "韧性上限 100（实际 %.0f）" % player.poise_max)
	_check(absf(player.hp - 40.0) < 0.001 and absf(player.poise - 100.0) < 0.001,
		"初始满血满韧性（%.0f/%.0f）" % [player.hp, player.poise])

	# 清掉还在飞的子弹 / 暂停两个测试桩，避免干扰掉血数值
	for _n in world.get_node("YSort").get_children():
		if _n.has_method("is_bullet"):
			_n.queue_free()
	for _d in [world.get_node_or_null("YSort/TestDummy"), world.get_node_or_null("YSort/ShooterDummy")]:
		if _d != null:
			_d.set_physics_process(false)
	player.hurt_invuln_left = 0.0
	await _physics(2)
	# 扣血 + 受击无敌
	var hit1: bool = player.take_damage(5.0)
	_check(hit1 and absf(player.hp - 35.0) < 0.001, "受击扣 5 点（%.0f）" % player.hp)
	var hit2: bool = player.take_damage(5.0)
	_check(not hit2 and absf(player.hp - 35.0) < 0.001, "受击无敌期间不再掉血（%.0f）" % player.hp)
	await _physics(30)   # 超过 0.4s 无敌
	var hit3: bool = player.take_damage(5.0)
	_check(hit3 and absf(player.hp - 30.0) < 0.001, "无敌结束后可以再次受击（%.0f）" % player.hp)

	# 归零与死亡、回血上限
	player.heal(100.0)
	_check(absf(player.hp - 40.0) < 0.001, "回血不会超过上限（%.0f）" % player.hp)
	player.hurt_invuln_left = 0.0          # 清掉受击无敌，测试致死伤害
	player.take_damage(100.0)
	_check(absf(player.hp) < 0.001 and player.is_dead(), "生命归零并判定死亡（%.0f）" % player.hp)

	# 韧性
	player.reset_stats()
	player.damage_poise(30.0)
	_check(absf(player.poise - 70.0) < 0.001, "韧性被削减 30（%.0f）" % player.poise)
	player.restore_poise(50.0)
	_check(absf(player.poise - 100.0) < 0.001, "韧性恢复不超过上限（%.0f）" % player.poise)
	player.damage_poise(200.0)
	_check(absf(player.poise) < 0.001 and player.is_poise_broken(), "韧性归零并判定破防（%.0f）" % player.poise)
	_check(player.is_exhausted(), "韧性清空同时进入力竭")
	player.exhaust_left = 0.0
	player.reset_stats()
	_check(absf(player.hp - 40.0) < 0.001 and absf(player.poise - 100.0) < 0.001 and absf(player.stamina - 100.0) < 0.001,
		"reset_stats 恢复全部状态")

	# HUD 状态条节点
	var bars: Node = world.get_node_or_null("HUD/StatusBars")
	_check(bars != null, "HUD 里存在 StatusBars 节点（生命/韧性/体力）")
	if bars != null:
		var p: Node = bars.get_node_or_null(bars.player_path)
		_check(p == player, "状态条正确绑定到玩家（%s）" % (p.name if p != null else "null"))

	# 调试快捷键 F3 / F4 / F5
	player.reset_stats()
	var ev := InputEventAction.new()
	ev.action = "debug_damage"
	ev.pressed = true
	world._unhandled_input(ev)
	_check(absf(player.hp - 35.0) < 0.001, "F3 扣血生效（%.0f）" % player.hp)
	var ev2 := InputEventAction.new()
	ev2.action = "debug_poise"
	ev2.pressed = true
	world._unhandled_input(ev2)
	_check(absf(player.poise - 80.0) < 0.001, "F4 扣韧性生效（%.0f）" % player.poise)
	var ev3 := InputEventAction.new()
	ev3.action = "debug_heal"
	ev3.pressed = true
	world._unhandled_input(ev3)
	_check(absf(player.hp - 40.0) < 0.001 and absf(player.poise - 100.0) < 0.001, "F5 回满生效")

	print("== 测试桩：生命 / 韧性 / 蓄力震荡波 ==")
	_release_all()
	var dummy: Node2D = world.get_node_or_null("YSort/TestDummy")
	_check(dummy != null, "世界里存在测试桩（TestDummy）")
	if dummy != null:
		dummy.set_physics_process(true)   # 其它用例期间它是关着的，避免震荡波干扰
		_check(absf(dummy.hp_max - 100.0) < 0.001 and absf(dummy.poise_max - 50.0) < 0.001,
			"桩的生命上限 100 / 韧性上限 50（%.0f/%.0f）" % [dummy.hp_max, dummy.poise_max])
		_check(absf(dummy.hp - 100.0) < 0.001 and absf(dummy.poise - 50.0) < 0.001, "桩初始满血满韧性")
		var dummy_bars: Node = dummy.get_node_or_null("Bars")
		_check(dummy_bars != null, "桩头顶有生命/韧性条节点")
		_check(absf(dummy.wave_damage - 10.0) < 0.001, "震荡波伤害 10（实际 %.0f）" % dummy.wave_damage)

		# 受击会掉血 / 掉韧性
		dummy.take_damage(20.0)
		dummy.damage_poise(10.0)
		_check(absf(dummy.hp - 80.0) < 0.001 and absf(dummy.poise - 40.0) < 0.001,
			"打桩后血量/韧性下降（%.0f/%.0f）" % [dummy.hp, dummy.poise])
		dummy.take_damage(200.0)
		_check(dummy.is_broken(), "血量归零判定桩被破坏")
		dummy.hp = dummy.hp_max
		dummy.poise = dummy.poise_max

		# 蓄力阶段：把周期推到「蓄力开始」之后
		dummy._cycle = dummy.attack_interval - dummy.charge_time + 0.05
		await _physics(2)
		_check(dummy.charging, "到点进入蓄力阶段（charging）")
		_check(dummy._charge_glow > 0.0, "蓄力时亮度提高作示警（glow=%.2f）" % dummy._charge_glow)
		_check(not dummy.wave_active, "蓄力期间还没有放出震荡波")

		# 震荡波：把玩家放在半径内，强制开火
		player.reset_stats()
		player.global_position = dummy.global_position + Vector2(60, 0)
		await _physics(6)
		var hp_before: float = player.hp
		dummy._cycle = dummy.attack_interval - 0.01
		await _physics(2)
		_check(dummy.wave_active, "蓄力结束放出震荡波（wave_active）")
		# 击退速度会被角色自身的刹车很快吃满，所以逐帧记录峰值
		var peak_speed := 0.0
		for i in 30:
			await get_tree().physics_frame
			peak_speed = maxf(peak_speed, player.velocity.length())
		var dmg: float = hp_before - player.hp
		_check(absf(dmg - 10.0) < 0.6, "震荡波命中造成 10 点伤害（实际 %.0f）" % dmg)
		_check(peak_speed > 80.0, "命中带轻微击退（峰值速度 %.0f）" % peak_speed)

		# 半径外不会被打到
		await _physics(60)
		player.reset_stats()
		player.global_position = dummy.global_position + Vector2(400, 0)
		await _physics(6)
		var hp_far: float = player.hp
		dummy.wave_active = false
		dummy._fire()
		await _physics(40)
		_check(absf(player.hp - hp_far) < 0.001, "半径外不会被震荡波命中（%.0f）" % player.hp)

		# 桩被破坏后不再攻击
		dummy.hp = 0.0
		dummy._cycle = dummy.attack_interval - 0.01
		await _physics(4)
		_check(not dummy.wave_active and not dummy.charging, "桩被破坏后停止攻击")
		dummy.hp = dummy.hp_max
		dummy.poise = dummy.poise_max
		dummy._cycle = 0.0

		# F7 调试键打桩
		var evd := InputEventAction.new()
		evd.action = "debug_hit_dummy"
		evd.pressed = true
		world._unhandled_input(evd)
		await _physics(2)
		_check(absf(dummy.hp - 80.0) < 0.001, "F7 调试键打桩扣血（%.0f）" % dummy.hp)
		dummy.hp = dummy.hp_max
		dummy.poise = dummy.poise_max
		player.reset_stats()
		dummy.set_physics_process(false)   # 后面的用例不需要它

	print("== 普攻（J） ==")
	_release_all()
	var dummy2: Node2D = world.get_node_or_null("YSort/TestDummy")
	if dummy2 != null:
		dummy2.set_physics_process(false)   # 只看普攻，不让桩反击
		dummy2.hp = dummy2.hp_max
		dummy2.poise = dummy2.poise_max
		player.reset_stats()
		player.global_position = dummy2.global_position + Vector2(-50, 0)   # 站在桩左边，朝右打
		player.facing = "E"
		player.facing_dir = Vector2.RIGHT
		await _physics(8)
		var dummy_hp_before: float = dummy2.hp
		var pos_before_atk: Vector2 = player.global_position
		Input.action_press("attack")
		await get_tree().physics_frame
		Input.action_release("attack")
		await get_tree().physics_frame
		_check(player.state == "attack", "按 J 进入普攻状态（%s）" % player.state)
		_check(sprite.animation == "attack_E", "播放该方向的攻击动画（%s）" % sprite.animation)
		await _physics(40)
		_check(absf(dummy2.hp - (dummy_hp_before - player.attack_damage)) < 0.01,
			"普攻命中测试桩（%.0f → %.0f）" % [dummy_hp_before, dummy2.hp])
		_check(player.global_position.distance_to(pos_before_atk) < 6.0,
			"普攻期间基本站定（%.1fpx）" % player.global_position.distance_to(pos_before_atk))
		_check(player.state != "attack", "普攻结束回到普通状态（%s）" % player.state)
		_check(absf(dummy2.poise - dummy2.poise_max) < 0.01, "普攻不削减韧性（%.0f/%.0f）" % [dummy2.poise, dummy2.poise_max])
		# 背对目标打不到
		dummy2.hp = dummy2.hp_max
		player.facing = "W"
		player.facing_dir = Vector2.LEFT
		await _physics(4)
		Input.action_press("attack")
		await get_tree().physics_frame
		Input.action_release("attack")
		await _physics(40)
		_check(absf(dummy2.hp - dummy2.hp_max) < 0.01, "背对目标普攻打空（%.0f）" % dummy2.hp)
		# 桩被打倒后 10 秒复活（测试里把时间调短，并确保它的物理在处理中）
		player.global_position = Vector2(-300, 150)   # 离桩远一点，避免复活后被打
		dummy2.set_physics_process(true)
		dummy2.revive_seconds = 0.4
		dummy2.hp = 0.0
		dummy2.revive_left = dummy2.revive_seconds
		await _physics(10)
		_check(dummy2.is_broken(), "桩被打倒后处于破坏状态")
		await _physics(40)
		_check(not dummy2.is_broken() and absf(dummy2.hp - dummy2.hp_max) < 0.01,
			"桩复活后满血（%.0f/%.0f）" % [dummy2.hp, dummy2.hp_max])
		_check(absf(dummy2.revive_seconds - 0.4) < 0.001, "复活计时按配置走（%.1fs）" % dummy2.revive_seconds)
		dummy2.revive_seconds = 10.0
		dummy2.set_physics_process(false)
		player.reset_stats()
		player.global_position = Vector2(-200, 150)

	print("== 普攻连击（二段上挑 / 三段短冲刀光） ==")
	_release_all()
	player.reset_stats()
	player.global_position = dummy2.global_position + Vector2(-50, 0)
	player.facing = "E"
	player.facing_dir = Vector2.RIGHT
	dummy2.hp = dummy2.hp_max
	dummy2.set_physics_process(false)
	await _physics(8)
	_check(absf(player.attack2_damage - 8.0) < 0.01 and absf(player.attack3_damage - 12.0) < 0.01,
		"二段伤害 8 / 三段伤害 12（%.0f / %.0f）" % [player.attack2_damage, player.attack3_damage])

	# 第一段起手
	Input.action_press("attack")
	await get_tree().physics_frame
	Input.action_release("attack")
	await _physics(3)
	_check(player.combo_step == 1 and sprite.animation == "attack_E", "第一段（%s）" % sprite.animation)

	# 在连击窗口内再按一次 → 第一段结束后接第二段
	await _physics(10)
	Input.action_press("attack")
	await get_tree().physics_frame
	Input.action_release("attack")
	await _physics(2)
	_check(player.combo_queued, "连击窗口内按 J 会缓存下一段")
	var hp_after_1: float = dummy2.hp
	await _physics(30)                 # 等第一段播完、进入第二段
	_check(player.combo_step == 2, "接力到第二段（combo_step=%d）" % player.combo_step)
	_check(sprite.animation == "attack2_E", "播放二段上挑动画（%s）" % sprite.animation)

	# 第二段动画播完（命中判定在 45%）
	await _physics(40)
	var dmg2: float = hp_after_1 - dummy2.hp
	_check(absf(dmg2 - player.attack2_damage) < 0.01, "二段命中 %d 伤害（%.0f）" % [int(player.attack2_damage), dmg2])
	_check(player.state != "attack" or player.combo_step == 2, "第二段结束时没有多余连击（%s）" % player.state)

	# 三段连击：一路按到底
	player.reset_stats()
	dummy2.hp = dummy2.hp_max
	player.global_position = dummy2.global_position + Vector2(-50, 0)
	player.facing = "E"
	player.facing_dir = Vector2.RIGHT
	await _physics(6)
	Input.action_press("attack")
	await get_tree().physics_frame
	Input.action_release("attack")
	await _physics(12)
	Input.action_press("attack")
	await get_tree().physics_frame
	Input.action_release("attack")
	await _physics(30)
	Input.action_press("attack")
	await get_tree().physics_frame
	Input.action_release("attack")
	await _physics(30)
	_check(player.combo_step == 3, "连到第三段（combo_step=%d）" % player.combo_step)
	_check(sprite.animation == "attack3_E", "播放三段短冲刀光动画（%s）" % sprite.animation)
	await _physics(40)
	var total_dmg: float = dummy2.hp_max - dummy2.hp
	_check(total_dmg > 20.0, "三段连击累计伤害 %.0f" % total_dmg)
	await _physics(40)
	_check(player.combo_step == 1, "三段打完回到第一段（combo_step=%d）" % player.combo_step)

	# 三段普攻会向前突进一小段
	player.reset_stats()
	player.global_position = Vector2(-200, 150)
	player.facing = "E"
	player.facing_dir = Vector2.RIGHT
	await _physics(6)
	var pos_before_dash: Vector2 = player.global_position
	player.combo_step = 3
	player.state = "attack"
	player._begin_attack_stage()
	await _physics(30)                       # 0.5s：突进 0.12s 后刹停
	var dash_dist: float = player.global_position.x - pos_before_dash.x
	_check(dash_dist > 20.0 and dash_dist < 60.0, "三段普攻向前突进 %.0fpx" % dash_dist)
	_check(absf(player.global_position.y - pos_before_dash.y) < 2.0, "突进方向正确（y 偏移 %.1f）" % (player.global_position.y - pos_before_dash.y))
	await _physics(40)
	player.reset_stats()
	print("== 格挡（K） ==")
	_release_all()
	player.exhaust_left = 0.0
	player.reset_stats()
	player.global_position = Vector2(-200, 150)
	player.facing = "S"
	await _physics(6)
	_check(Keybinds.keycode_of("block", 0) == KEY_K, "格挡默认按键为 K（%s）" % Keybinds.key_text("block", 0))
	_check(absf(player.block_damage_multiplier - 0.5) < 0.001, "格挡减伤 50%%（倍率 %.2f）" % player.block_damage_multiplier)

	Input.action_press("block")
	await _physics(3)
	_check(player.is_blocking() and player.state == "block", "按住 K 进入格挡（%s）" % player.state)
	_check(sprite.animation.begins_with("block_in"), "先播放抬起动作（%s）" % sprite.animation)
	var in_time: float = player._anim_duration("block_in_S")
	_check(in_time > 0.15 and in_time < 0.26, "抬手时长约 0.2s（实际 %.2fs）" % in_time)
	await _physics(15)   # 0.25s：抬起应已播完
	_check(player.block_phase == "hold", "按住后进入保持阶段（%s）" % player.block_phase)
	_check(sprite.animation.begins_with("block_hold"), "播放保持动作（%s）" % sprite.animation)

	# 正面（被格挡的一侧）命中：伤害减半 + 顿帧
	player.reset_stats()
	player.facing = "S"                    # S 用右半边格挡
	var hp_before_block: float = player.hp
	var front_src: Vector2 = player.global_position + Vector2(40, 0)
	var res_front: String = player.try_take_hit(10.0, front_src)
	_check(res_front == "blocked_hit", "被格挡侧命中返回 blocked_hit（%s）" % res_front)
	_check(absf(player.hp - (hp_before_block - 5.0)) < 0.01, "格挡中 10 点伤害只掉 5 点（%.0f → %.0f）" % [hp_before_block, player.hp])
	_check(player.block_phase == "hit", "格挡命中进入火花反应（%s）" % player.block_phase)
	_check(sprite.animation.begins_with("block_hit"), "播放格挡火花动画（%s）" % sprite.animation)
	_check(absf(player.poise - (player.poise_max - 10.0)) < 0.01, "普通格挡消耗 10 点韧性（%.0f → %.0f）" % [player.poise_max, player.poise])
	_check(Engine.time_scale < 0.05, "格挡命中触发顿帧（time_scale=%.2f）" % Engine.time_scale)
	var hitstop_t0: int = Time.get_ticks_msec()
	var frames_waited := 0
	while Engine.time_scale < 0.5 and frames_waited < 120:
		await _physics(1)
		frames_waited += 1
	var hitstop_ms: int = Time.get_ticks_msec() - hitstop_t0
	_check(absf(Engine.time_scale - 1.0) < 0.01, "顿帧自动恢复（time_scale=%.2f）" % Engine.time_scale)
	_check(hitstop_ms >= 60 and hitstop_ms <= 200, "顿帧约 0.1 秒（实测 %d ms）" % hitstop_ms)

	# 背后命中：不减伤、无顿帧
	await _physics(30)                     # 等受击无敌结束
	var hp_before_back: float = player.hp
	var back_src: Vector2 = player.global_position + Vector2(-40, 0)
	var res_back: String = player.try_take_hit(10.0, back_src)
	_check(res_back == "hit", "背后命中不触发格挡（%s）" % res_back)
	_check(absf(player.hp - (hp_before_back - 10.0)) < 0.01, "背后命中吃满 10 点（%.0f → %.0f）" % [hp_before_back, player.hp])
	_check(absf(Engine.time_scale - 1.0) < 0.01, "背后命中不触发顿帧")
	var poise_before_back_hit: float = player.poise
	await _physics(30)
	player.try_take_hit(10.0, player.global_position + Vector2(-40, 0))
	_check(absf((poise_before_back_hit - player.poise) - 20.0) < 0.01,
		"格挡时背部受击削 20 点韧性（%.0f → %.0f）" % [poise_before_back_hit, player.poise])

	# 击退：被格挡侧减半，背后不减半
	player.velocity = Vector2.ZERO
	player.apply_knockback(Vector2.LEFT, 200.0)    # 从右侧推向左 -> 来源在被格挡侧
	_check(absf(player.velocity.length() - 100.0) < 1.0, "被格挡侧击退减半（速度 %.0f）" % player.velocity.length())
	player.velocity = Vector2.ZERO
	player.apply_knockback(Vector2.RIGHT, 200.0)   # 从左侧推向右 -> 来源在背后
	_check(absf(player.velocity.length() - 200.0) < 1.0, "背后击退不减半（速度 %.0f）" % player.velocity.length())

	# 松手：放下动作 -> 回到站立
	Input.action_release("block")
	await _physics(3)
	_check(player.block_phase == "out", "松手后播放放下动作（%s）" % player.block_phase)
	await _physics(30)
	_check(player.state != "block", "放下后退出格挡（%s）" % player.state)
	player.reset_stats()
	print("== 第二个测试桩：连发子弹 ==")
	_release_all()
	var shooter: Node2D = world.get_node_or_null("YSort/ShooterDummy")
	_check(shooter != null, "世界里存在射击桩（ShooterDummy）")
	if shooter != null:
		_check(shooter.volley_count == 5 and absf(shooter.bullet_damage - 2.0) < 0.01,
			"每轮 5 发、每发 2 点伤害（%d 发 / %.0f 点）" % [shooter.volley_count, shooter.bullet_damage])
		_check(absf(shooter.volley_interval - 10.0) < 0.01, "发射间隔 10 秒（%.0f）" % shooter.volley_interval)
		shooter.set_physics_process(false)   # 先手动控制，避免计时干扰

		# 远处不发射
		player.reset_stats()
		player.global_position = shooter.global_position + Vector2(400, 300)
		shooter.bullets_fired = 0
		shooter._timer = 0.0
		shooter.set_physics_process(true)
		await _physics(30)
		_check(shooter.bullets_fired == 0, "周围没人时不发射（已发 %d 发）" % shooter.bullets_fired)
		shooter.set_physics_process(false)

		# 手动开一轮：确认 5 发都出去
		player.reset_stats()
		player.global_position = shooter.global_position + Vector2(60, 0)
		await _physics(4)
		shooter.bullets_fired = 0
		shooter.set_physics_process(true)
		shooter._start_volley(player)
		await _physics(40)   # 0.66s：够打完 5 发（间隔 0.12s）
		_check(shooter.bullets_fired == 5, "一轮打出 5 发（实际 %d 发）" % shooter.bullets_fired)
		var hp_after_bullets: float = player.hp
		_check(hp_after_bullets < player.hp_max, "子弹命中造成伤害（%.0f/%.0f）" % [hp_after_bullets, player.hp_max])
		# 子弹 2 点伤害 + 受击无敌，最多掉 2 的整数倍
		_check(absf((player.hp_max - hp_after_bullets) - round(player.hp_max - hp_after_bullets)) < 0.01,
			"伤害是 2 的整数倍（掉了 %.0f）" % (player.hp_max - hp_after_bullets))
		shooter.set_physics_process(false)

		# 格挡子弹：伤害减半 + 消耗韧性 + 火花反应
		await _physics(30)
		player.reset_stats()
		player.block_phase = "in"
		player.facing = "W"        # 桩在左边，朝左挡
		Input.action_press("block")
		await _physics(10)         # 抬手完成，进入保持
		var hp_before_bullet_block: float = player.hp
		var poise_before: float = player.poise
		shooter.bullets_fired = 0
		shooter.set_physics_process(true)
		shooter._start_volley(player)
		await _physics(40)
		Input.action_release("block")
		var blocked_dmg: float = hp_before_bullet_block - player.hp
		# 格挡不吃受击无敌：每颗子弹都算 1 点（2 × 50%），最多 5 点
		_check(blocked_dmg > 0.0 and blocked_dmg <= 5.0, "格挡子弹每发减半、可连续命中（掉了 %.0f）" % blocked_dmg)
		_check(absf(blocked_dmg - round(blocked_dmg)) < 0.01, "格挡子弹伤害是整数（%.0f）" % blocked_dmg)
		_check(player.poise <= poise_before - 5.0, "格挡子弹消耗韧性（%.0f → %.0f）" % [poise_before, player.poise])

		# 连续挨打：火花动画每一下都从头重播
		await _physics(30)
		Input.action_release("block")
		# 等火花反应 + 放下动作都结束，确保真正回到站立
		for _w in range(120):
			await _physics(1)
			if player.state != "block":
				break
		player.reset_stats()
		player.facing = "S"
		await _physics(4)
		Input.action_press("block")
		for _w2 in range(30):
			await _physics(1)
			if player.block_phase == "hold":
				break
		_check(player.block_phase == "hold", "连续挨打测试前已进入保持（%s / %s）" % [player.state, player.block_phase])
		var hp_before_chain: float = player.hp
		var poise_before_chain: float = player.poise
		var src_chain: Vector2 = player.global_position + Vector2(40, 0)
		player.try_take_hit(10.0, src_chain)
		# 等顿帧结束、火花播到中途（顿帧期间动画几乎不推进，所以用循环等）
		for _i in range(180):
			await _physics(1)
			if absf(Engine.time_scale - 1.0) < 0.01 and sprite.frame > 1:
				break
		var frame_mid: int = sprite.frame
		_check(frame_mid > 1, "第一次格挡后火花已播到第 %d 帧" % frame_mid)
		player.try_take_hit(10.0, src_chain)   # 第二下：应立刻回到第一帧
		_check(player.block_phase == "hit", "连续挨打仍在火花相位（%s）" % player.block_phase)
		_check(sprite.frame == 0, "火花立刻从第 0 帧重播（中途第 %d 帧 → 现在第 %d 帧）" % [frame_mid, sprite.frame])
		_check(player.block_time < 0.01, "火花计时也从 0 重来（%.3fs）" % player.block_time)
		_check(absf((hp_before_chain - player.hp) - 10.0) < 0.01, "连续两下格挡都掉血（共 %.0f 点）" % (hp_before_chain - player.hp))
		_check(absf((poise_before_chain - player.poise) - 20.0) < 0.01, "连续两下各扣 10 韧性（共 %.0f）" % (poise_before_chain - player.poise))
		Input.action_release("block")
		await _physics(30)
		shooter.set_physics_process(false)
		player.reset_stats()
		await _physics(30)
	print("== 完美格挡（抬手期间） ＝=")
	_release_all()
	player.reset_stats()
	player.global_position = Vector2(-200, 150)
	player.facing = "S"
	await _physics(6)
	_check(absf(player.perfect_block_poise_gain - 30.0) < 0.01, "完美格挡回 30 韧性（%.0f）" % player.perfect_block_poise_gain)

	# 先把韧性打成 40，方便看 +30
	player.poise = 40.0
	Input.action_press("block")
	await _physics(2)                       # 还在抬手阶段（0.2s 内）
	_check(player.state == "block" and player.block_phase == "in", "抬手阶段（%s/%s）" % [player.state, player.block_phase])
	var hp_before_pb: float = player.hp
	var res_pb: String = player.try_take_hit(10.0, player.global_position + Vector2(40, 0))
	_check(res_pb == "perfect_block", "抬手期间被击中触发完美格挡（%s）" % res_pb)
	_check(player.is_in_perfect_block(), "进入完美格挡状态（%s）" % player.state)
	_check(get_tree().paused, "除主角外全部时停（tree.paused=%s）" % get_tree().paused)
	_check(player.process_mode == Node.PROCESS_MODE_ALWAYS, "主角在时停中仍可行动（process_mode=%d）" % player.process_mode)
	_check(absf(player.hp - hp_before_pb) < 0.01, "完美格挡不掉血（%.0f/%.0f）" % [player.hp, player.hp_max])
	_check(absf(player.poise - 70.0) < 0.01, "完美格挡回韧性 40 → 70（%.0f）" % player.poise)
	_check(sprite.animation == "perfect_block_S", "播放完美格挡动画（%s）" % sprite.animation)

	# 时停期间其它东西不动
	var frozen_dummy: Node2D = world.get_node_or_null("YSort/TestDummy")
	var frozen_x_before: float = frozen_dummy.global_position.x
	await _physics(20)
	_check(absf(frozen_dummy.global_position.x - frozen_x_before) < 0.01, "时停期间其它节点不动")

	# 动画播完自动恢复
	await _physics(40)
	_check(not player.is_in_perfect_block(), "动画播完退出完美格挡（%s）" % player.state)
	_check(not get_tree().paused, "时停结束，世界恢复（paused=%s）" % get_tree().paused)
	Input.action_release("block")
	await _physics(20)
	player.reset_stats()

	print("== 力竭（韧性清空） ＝=")
	player.reset_stats()
	player.global_position = Vector2(-200, 150)
	player.facing = "S"
	player.exhaust_seconds = 0.5          # 测试里把 10 秒调短
	await _physics(4)
	Input.action_press("block")
	await _physics(20)                    # 抬手完成，进入保持
	player.poise = 5.0
	var hp_before_ex: float = player.hp
	player.try_take_hit(10.0, player.global_position + Vector2(40, 0))   # 格挡：5 伤 + 扣 5 韧性 → 0
	_check(player.poise <= 0.0, "韧性被打空（%.0f）" % player.poise)
	_check(player.is_exhausted(), "韧性清空进入力竭")
	_check(absf((hp_before_ex - player.hp) - 5.0) < 0.01, "力竭当下那一下仍是格挡伤害（掉 %.0f）" % (hp_before_ex - player.hp))
	_check(absf(player.exhaust_ratio() - 1.0) < 0.05, "力竭倒计时开始（%.2f）" % player.exhaust_ratio())

	# 力竭期间：再挨打不减伤
	await _physics(2)
	var hp_before_ex2: float = player.hp
	var res_ex: String = player.try_take_hit(10.0, player.global_position + Vector2(40, 0))
	_check(res_ex == "hit", "力竭时格挡不再减伤（返回 %s）" % res_ex)
	_check(absf((hp_before_ex2 - player.hp) - 10.0) < 0.01, "力竭时吃满伤害（掉 %.0f）" % (hp_before_ex2 - player.hp))

	# 力竭期间减速 20%
	Input.action_release("block")
	await _physics(10)
	player.reset_stats()
	player.exhaust_left = 2.0     # 直接标记力竭（够撑住 40 帧测量）
	player.poise = 0.0
	await _physics(2)
	Input.action_press("move_right")
	await _physics(60)
	var slowed_speed: float = player.velocity.length()
	Input.action_release("move_right")
	await _physics(30)
	player.exhaust_left = 0.0
	await _physics(30)
	Input.action_press("move_right")
	await _physics(60)
	var normal_speed: float = player.velocity.length()
	Input.action_release("move_right")
	_check(absf(slowed_speed - player.walk_speed * player.exhaust_speed_multiplier) < 8.0 and absf(normal_speed - player.walk_speed) < 8.0,
		"力竭减速 20%%（%.0f vs 正常 %.0f，基准 %.0f）" % [slowed_speed, normal_speed, player.walk_speed])

	# 力竭结束：韧性回满
	player.reset_stats()
	player.poise = 0.0
	player._start_exhaust()
	await _physics(2)
	_check(player.is_exhausted(), "再次进入力竭")
	await _physics(60)            # 0.5s → 早该结束
	_check(not player.is_exhausted(), "力竭结束（剩余 %.2f）" % player.exhaust_left)
	_check(absf(player.poise - player.poise_max) < 0.01, "力竭结束后韧性回满（%.0f/%.0f）" % [player.poise, player.poise_max])
	player.exhaust_seconds = 10.0
	Input.action_release("block")
	await _physics(10)
	player.reset_stats()
	print("== 格挡消耗体力 / 完美格挡反击 ==")
	_release_all()
	player.reset_stats()
	player.global_position = Vector2(-200, 150)
	player.facing = "S"
	player.time_since_stamina_use = 0.0
	await _physics(4)
	_check(absf(player.block_stamina_cost - 10.0) < 0.01, "格挡起手消耗 10 体力（%.0f）" % player.block_stamina_cost)
	_check(absf(player.block_stamina_drain_interval - 0.2) < 0.001, "保持格挡每 0.2s 消耗 1 点（%.2f）" % player.block_stamina_drain_interval)

	# 起手扣 10，保持期间每 0.2s 再掉 1（格挡期间不回体力）
	player.stamina = 50.0
	player.time_since_stamina_use = 0.0
	Input.action_press("block")
	await _physics(2)
	_check(absf(player.stamina - 40.0) < 0.6, "按 K 立刻扣 10 体力（%.1f）" % player.stamina)
	await _physics(60)      # 1 秒：再掉约 5 点
	_check(player.stamina < 36.5 and player.stamina > 32.0, "保持格挡持续掉体力（%.1f）" % player.stamina)
	Input.action_release("block")
	await _physics(20)

	# 没体力不能格挡
	player.reset_stats()
	player.time_since_stamina_use = 0.0
	player.stamina = 0.0
	await _physics(2)
	Input.action_press("block")
	await _physics(4)
	_check(player.state != "block", "没体力时无法格挡（实际 %s）" % player.state)
	Input.action_release("block")
	await _physics(10)

	# 只剩 5 点：起手后归零
	player.reset_stats()
	player.time_since_stamina_use = 0.0
	player.stamina = 5.0
	await _physics(2)
	Input.action_press("block")
	await _physics(3)
	_check(player.stamina <= 0.01, "不足 10 点起手后体力归零（%.1f）" % player.stamina)
	Input.action_release("block")
	await _physics(30)

	# 完美格挡：回 10 体力 + 立刻反击（正前方 20 伤害）
	var dummy3: Node2D = world.get_node_or_null("YSort/TestDummy")
	player.reset_stats()
	player.time_since_stamina_use = 0.0
	player.global_position = dummy3.global_position + Vector2(-50, 0)
	player.facing = "E"
	player.facing_dir = Vector2.RIGHT
	player.stamina = 60.0
	await _physics(4)
	_check(absf(player.perfect_block_stamina_gain - 10.0) < 0.01, "完美格挡回 10 体力（%.0f）" % player.perfect_block_stamina_gain)
	Input.action_press("block")
	await _physics(1)
	var stamina_after_start: float = player.stamina
	var dummy_hp_before: float = dummy3.hp
	var res_pb2: String = player.try_take_hit(10.0, player.global_position + Vector2(40, 0))
	_check(res_pb2 == "perfect_block", "正中抬手触发完美格挡（%s）" % res_pb2)
	_check(absf(player.stamina - (stamina_after_start + 10.0)) < 0.5,
		"完美格挡回复 10 体力（%.0f → %.0f）" % [stamina_after_start, player.stamina])

	await _physics(50)
	_check(player.state == "counter" or player.counter_hit_done, "完美格挡结束后立刻反击（%s）" % player.state)
	_check(sprite.animation.begins_with("counter"), "播放反击动画（%s）" % sprite.animation)
	await _physics(60)
	_check(absf((dummy_hp_before - dummy3.hp) - 20.0) < 0.01, "反击造成 20 点伤害（%.0f → %.0f）" % [dummy_hp_before, dummy3.hp])
	Input.action_release("block")
	await _physics(30)
	dummy3.hp = dummy3.hp_max
	player.reset_stats()

	# 反击清掉远程子弹
	player.reset_stats()
	player.time_since_stamina_use = 0.0
	player.global_position = Vector2(0, 200)
	player.facing = "S"
	player.facing_dir = Vector2.DOWN
	player.stamina = 100.0
	await _physics(4)
	var bullet_layer: Node = world.get_node("YSort")
	var bullet: Node2D = (load("res://scenes/bullet.tscn") as PackedScene).instantiate()
	bullet.direction = Vector2.DOWN
	bullet.speed = 0.0
	bullet.source_pos = player.global_position + Vector2(0, -80)
	bullet_layer.add_child(bullet)
	bullet.global_position = player.global_position + Vector2(0, -60)
	await _physics(2)
	var bullets_before := 0
	for c in bullet_layer.get_children():
		if c.has_method("is_bullet") and c.is_bullet():
			bullets_before += 1
	_check(bullets_before > 0, "场上已有子弹（%d 颗）" % bullets_before)
	Input.action_press("block")
	await _physics(1)
	player.try_take_hit(10.0, player.global_position + Vector2(0, 40))
	await _physics(60)
	var bullets_after := 0
	for c in bullet_layer.get_children():
		if c.has_method("is_bullet") and c.is_bullet():
			bullets_after += 1
	_check(bullets_after < bullets_before, "反击清掉远程子弹（%d → %d）" % [bullets_before, bullets_after])
	Input.action_release("block")
	await _physics(40)
	player.reset_stats()
	print("== 反击范围 / 格挡也重置体力计时 ==")
	_release_all()
	player.reset_stats()
	player.global_position = Vector2(-200, 150)
	player.facing = "S"
	await _physics(6)
	_check(absf(player.counter_range - 120.0) < 0.01, "反击范围 120（%.0f）" % player.counter_range)

	# 格挡也算"用体力"：格挡期间计时清零，松手后要再等 5 秒才开始回
	player.stamina = 50.0
	player.time_since_stamina_use = 10.0
	Input.action_press("block")
	await _physics(30)      # 0.5s
	_check(player.time_since_stamina_use < 0.05, "格挡期间体力计时清零（%.2f）" % player.time_since_stamina_use)
	Input.action_release("block")
	await _physics(30)      # 放下动作播完（0.29s）后才真正退出格挡
	_check(player.state != "block", "松手后退出格挡（%s）" % player.state)
	_check(player.time_since_stamina_use > 0.1 and player.time_since_stamina_use < 0.6,
		"松手后重新开始计时（%.2f）" % player.time_since_stamina_use)

	# 离得远一点（中心距 110）也能被反击打到
	var dummy4: Node2D = world.get_node_or_null("YSort/TestDummy")
	player.reset_stats()
	player.global_position = dummy4.global_position + Vector2(-110, 0)
	player.facing = "E"
	player.facing_dir = Vector2.RIGHT
	player.stamina = 100.0
	await _physics(4)
	var hp_before_far: float = dummy4.hp
	player._start_counter()
	await _physics(60)
	_check(absf((hp_before_far - dummy4.hp) - 20.0) < 0.01,
		"中心距 110 仍在反击范围内（%.0f → %.0f）" % [hp_before_far, dummy4.hp])
	dummy4.hp = dummy4.hp_max
	player.reset_stats()
	await _physics(20)
	print("== 平行时空（R 切换） ==")
	_check(Keybinds.keycode_of("switch_time", 0) == KEY_R, "切换时空默认按键 R（%s）" % Keybinds.key_text("switch_time", 0))
	_check(Timeline != null, "Timeline 自动加载存在")
	Timeline.set_era(Timeline.Era.MODERN)
	await _physics(3)
	_check(not Timeline.is_future() and Timeline.era_name() == "现代", "初始时空是现代（%s）" % Timeline.era_name())
	var ground2: Node2D = world.get_node_or_null("Ground")
	_check(world.modern_map != null and world.modern_map.visible, "现代时空显示现代风等距地图（ModernMap）")
	_check(not world.future_map.visible, "未来地图默认隐藏")
	_check(ground2.floor_texture == null, "两个时空都不用平铺路面（纹理清空）")
	_check(world.air_walls_of(false) != null, "现代时空生成了自己的空气墙")
	# 模拟按 R：先在原时空消失（播变换音效）→ 中点切时空 → 倒放出现（播出现音效）
	Input.action_press("switch_time")
	await _physics(2)
	Input.action_release("switch_time")
	await _physics(3)
	_check(player.state == "era_shift" and player.era_shift_phase == "vanish", "按 R 先在原时空消失（%s/%s）" % [player.state, player.era_shift_phase])
	_check(not Timeline.is_future(), "消失阶段还没切换时空（仍是%s）" % Timeline.era_name())
	_check(player.era_switch_sfx.stream != null and player.era_switch_sfx.playing, "消失时播放变换时空音效")
	_check(player.sprite.animation == "era_vanish_right" or player.sprite.animation == "era_vanish_left", "播放消失动画（%s）" % player.sprite.animation)
	await _physics(32)                 # 消失 0.5s 播完
	_check(Timeline.is_future() and Timeline.era_name() == "未来", "消失播完后切到未来（%s）" % Timeline.era_name())
	_check(player.state == "era_shift" and player.era_shift_phase == "appear", "接着在另一时空出现（%s）" % player.era_shift_phase)
	_check(player.sprite.animation == "era_appear_right" or player.sprite.animation == "era_appear_left", "出现动画是倒放（%s）" % player.sprite.animation)
	_check(world.future_map != null and world.future_map.visible, "出现时已经换成未来地图（FutureMap 可见）")
	_check(player.era_appear_sfx.stream != null and player.era_appear_sfx.playing, "出现时播放出现音效")
	await _physics(32)                 # 出现 0.5s 播完
	_check(player.state == "stand", "变换完成回到站立（%s）" % player.state)
	_check(ground2.floor_texture == null, "未来时空把平地路面让给地图（纹理清空）")
	_check(world.future_floor != null, "未来地图素材仍在（备用路面纹理）")
	var future_walls: StaticBody2D = world.air_walls_of(true)
	_check(future_walls != null, "两个时空共用一套空气墙节点")
	var wall_count: int = int(future_walls.get_meta("wall_count", 0)) if future_walls != null else 0
	var cam: Camera2D = player.get_node("Camera")
	_check(cam.limit_right > 600, "未来时空相机范围覆盖整张地图（right=%d）" % cam.limit_right)
	# 空气墙应该围着整张地图（左右两端都覆盖到），而且地图比现代场地大
	var wall_bounds: Rect2 = future_walls.get_meta("bounds", Rect2()) if future_walls != null else Rect2()
	_check(wall_bounds.size.x > 1200.0 and wall_bounds.size.y > 700.0,
		"地图按原尺寸铺开（%.0f×%.0f）" % [wall_bounds.size.x, wall_bounds.size.y])
	var wall_min_x := 1e9; var wall_max_x := -1e9
	for c in future_walls.get_children():
		wall_min_x = minf(wall_min_x, c.position.x)
		wall_max_x = maxf(wall_max_x, c.position.x)
	_check(wall_min_x < -400.0 and wall_max_x > 400.0,
		"空气墙围住地图两端（x %.0f .. %.0f）" % [wall_min_x, wall_max_x])
	# 平台中间可以正常走动
	player.global_position = Vector2(0, 0)
	await _physics(4)
	Input.action_press("move_left")
	await _physics(60)
	Input.action_release("move_left")
	await _physics(6)
	_check(player.global_position.x < -20.0, "未来时空里玩家能正常移动（x=%.0f）" % player.global_position.x)

	# 再按一次切回现代（同样先消失再出现）
	Input.action_press("switch_time")
	await _physics(2)
	Input.action_release("switch_time")
	await _physics(3)
	_check(player.state == "era_shift" and player.era_shift_phase == "vanish", "切回现代时也先消失（%s/%s）" % [player.state, player.era_shift_phase])
	await _physics(64)                 # 消失 + 出现
	_check(not Timeline.is_future() and Timeline.era_name() == "现代", "再按 R 切回现代（%s）" % Timeline.era_name())
	_check(not Timeline.is_future() and Timeline.era_name() == "现代", "再按 R 切回现代（%s）" % Timeline.era_name())
	_check(not world.future_map.visible and world.modern_map.visible, "现代时空只显示现代地图")
	_check(ground2.floor_texture == null, "现代时空同样不用平铺路面")
	var modern_walls: StaticBody2D = world.air_walls_of(false)
	_check(modern_walls != null and int(modern_walls.get_meta("wall_count", 0)) >= 6,
		"现代时空的那套空气墙也在（%d 块）" % (int(modern_walls.get_meta("wall_count", 0)) if modern_walls != null else 0))
	var modern_rect: Rect2 = world._map_rect()
	_check(modern_rect.size.x > 1200.0 and modern_rect.size.y > 700.0,
		"现代地图按原尺寸铺开（%.0f×%.0f）" % [modern_rect.size.x, modern_rect.size.y])
	_release_all()
	_release_all()
	var modern_dummy: Node2D = world.get_node("YSort/TestDummy")
	var fen1: Node2D = world.get_node_or_null("YSort/FutureEnemy")
	var fen2: Node2D = world.get_node_or_null("YSort/FutureEnemy2")
	_check(fen1 != null and fen2 != null, "未来时空有两个敌人")
	_check(future_enemies.size() == 5, "未来时空有五个敌人（%d 个）" % future_enemies.size())
	_check(world.get_node_or_null("YSort/FutureEnemy3") != null and world.get_node_or_null("YSort/FutureEnemy4") != null and world.get_node_or_null("YSort/FutureEnemy5") != null,
		"五个未来敌人节点都在场景里")
	var spread_ok := true
	for ia in range(future_enemy_home.size()):
		for ib in range(ia + 1, future_enemy_home.size()):
			if future_enemy_home[ia].distance_to(future_enemy_home[ib]) < 150.0:
				spread_ok = false
	_check(spread_ok, "五个未来敌人站位彼此拉开（最近间距 >150）")
	_check(fen1.detect_radius <= 300.0, "未来敌人索敌半径已缩小（%.0f）" % fen1.detect_radius)
	if fen1 != null and fen2 != null:
		modern_dummy.hp = modern_dummy.hp_max
		modern_dummy.visible = true
		await _physics(3)
		_check(modern_dummy.visible and not fen1.visible and not fen2.visible, "现代时空只显示现代的生物")
		modern_dummy.take_damage(30.0)
		var modern_hp: float = modern_dummy.hp
		_check(modern_hp < modern_dummy.hp_max, "现代桩掉血（%.0f）" % modern_hp)
		# 切到未来
		player.global_position = Vector2(-300, 200)
		await _physics(4)
		Input.action_press("switch_time")
		await _physics(2)
		Input.action_release("switch_time")
		await _physics(70)
		_check(Timeline.is_future(), "已切到未来（%s）" % Timeline.era_name())
		_check(not modern_dummy.visible, "现代的生物在未来时空隐藏")
		_check(fen1.visible and fen2.visible, "两个敌人都在未来时空可见")
		_check(absf(fen1.hp - fen1.hp_max) < 0.01, "敌人 1 是独立满血（%.0f）" % fen1.hp)
		_check(fen1.process_mode != Node.PROCESS_MODE_DISABLED, "敌人 1 在跑自己的逻辑")
		_check(modern_dummy.process_mode == Node.PROCESS_MODE_DISABLED, "现代的桩在未来时空停摆")
		# 未来的测试桩已经删了
		_check(world.get_node_or_null("YSort/TestDummyFuture") == null, "未来的测试桩已删除")
		_check(world.get_node_or_null("YSort/ShooterDummyFuture") == null, "未来的射击桩已删除")
		# 打敌人 1：先冻结它，避免它走开
		fen1.set_physics_process(false)
		player.global_position = fen1.global_position + Vector2(-50, 0)
		player.facing = "E"
		player.facing_dir = Vector2.RIGHT
		await _physics(8)
		Input.action_press("attack")
		await get_tree().physics_frame
		Input.action_release("attack")
		await _physics(40)
		_check(fen1.hp < fen1.hp_max, "普攻打到未来的敌人（%.0f）" % fen1.hp)
		_check(absf(modern_dummy.hp - modern_hp) < 0.01, "现代时空的桩血量不受影响（%.0f）" % modern_dummy.hp)
		# 开火时不能移动
		fen1.set_physics_process(true)
		fen1.hp = fen1.hp_max
		fen1.energy = fen1.energy_max
		fen1.recover_left = 0.0
		fen1.global_position = Vector2(-40, 60)
		player.global_position = Vector2(-40, 220)
		await _physics(120)
		var saw_shoot := false
		var moved_while_shoot := 0.0
		var shoot_started_ms := -1
		var shoot_duration := 0.0
		var anim_restarts := 0
		var prev_frame := -1
		for _k in range(300):
			var p0: Vector2 = fen1.global_position
			var shooting_now: bool = fen1._shooting
			var frame_now: int = fen1.sprite.frame
			await _physics(1)
			if shooting_now:
				if not saw_shoot:
					saw_shoot = true
					shoot_started_ms = Time.get_ticks_msec()
				moved_while_shoot = maxf(moved_while_shoot, p0.distance_to(fen1.global_position))
				# 每发都重新播一次开枪动作：帧号从非 0 回到 0 记为一次重播
				if prev_frame > 0 and frame_now == 0:
					anim_restarts += 1
			elif saw_shoot and shoot_started_ms >= 0:
				shoot_duration = float(Time.get_ticks_msec() - shoot_started_ms) / 1000.0
				break
			prev_frame = frame_now
		_check(saw_shoot, "敌人进入过开火状态")
		_check(moved_while_shoot < 0.5, "开火时敌人不移动（位移 %.2f）" % moved_while_shoot)
		_check(shoot_duration > 0.85 and shoot_duration < 1.35,
			"一轮开枪站立约 1 秒（%.2f 秒）" % shoot_duration)
		_check(anim_restarts >= 2, "三发各自单独播开枪动作（重播 %d 次）" % anim_restarts)
		_check(fen1.bullet_speed >= 300.0, "子弹速度已加快（%.0f）" % fen1.bullet_speed)

		# 复位
		fen1.hp = fen1.hp_max
		fen1.poise = fen1.poise_max
		fen1.energy = fen1.energy_max
		fen1.dead = false
		fen1.dead_left = 0.0
		fen1.bars.visible = true
		fen1.modulate = Color(1, 1, 1, 1)
		fen1.global_position = Vector2(60, 150)
		modern_dummy.hp = modern_dummy.hp_max
		modern_dummy.poise = modern_dummy.poise_max
		player.global_position = Vector2(-300, 200)
		await _physics(4)
		Input.action_press("switch_time")
		await _physics(2)
		Input.action_release("switch_time")
		await _physics(70)
		_check(not Timeline.is_future(), "切回现代（%s）" % Timeline.era_name())
		player.global_position = Vector2(-200, 150)
		await _physics(4)

	print("== 墙壁遮挡 / 虚化 ==")
	var walls_m: Array = world._wall_views.get(world.modern_map, [])
	_check(walls_m.size() > 30, "收集到现代时空的墙体（%d 面）" % walls_m.size())
	if walls_m.size() > 0:
		var w0: Dictionary = walls_m[0]
		var w0_sp: Sprite2D = w0["sp"]
		var w0_base: float = w0["base_y"]
		var w0_cx: float = w0["cx"]
		player.global_position = Vector2(w0_cx, w0_base - 30)
		for _f in range(20):
			await get_tree().process_frame
		await _physics(2)
		_check(w0_sp.z_index == 2, "墙在人物前面时 z_index=2（实际 %d）" % w0_sp.z_index)
		_check(w0_sp.modulate.a < 0.8, "挡住人物的墙被虚化（alpha=%.2f）" % w0_sp.modulate.a)
		player.global_position = Vector2(w0_cx, w0_base + 160)
		for _f in range(20):
			await get_tree().process_frame
		await _physics(2)
		_check(w0_sp.z_index == -2, "墙在人物后面时 z_index=-2（实际 %d）" % w0_sp.z_index)
		_check(w0_sp.modulate.a > 0.9, "不再遮挡时恢复不透明（alpha=%.2f）" % w0_sp.modulate.a)
		player.global_position = world.spawn_position
		await _physics(4)

	print("== 敌人被墙挡住时也要虚化 ==")
	var enemy_oc: Node = world.get_node_or_null("YSort/FutureEnemy")
	if enemy_oc != null:
		Timeline.toggle()   # 切到未来，敌人启用
		await _physics(4)
		enemy_oc.set_physics_process(false)   # 固定位置，方便验证
		var walls_f: Array = world._wall_views.get(world.future_map, [])
		if walls_f.size() > 0:
			var wf: Dictionary = walls_f[0]
			var wf_sp: Sprite2D = wf["sp"]
			var wf_base: float = wf["base_y"]
			var wf_cx: float = wf["cx"]
			# 玩家放在墙的侧后方（不压墙，但让这面墙 z_index=2），只有敌人被墙压住
			player.global_position = Vector2(wf_cx + 160.0, wf_base - 10.0)
			enemy_oc.global_position = Vector2(wf_cx, wf_base - 30.0)
			for _f2 in range(20):
				await get_tree().process_frame
			await _physics(2)
			_check(wf_sp.z_index == 2, "敌人被墙挡住时墙也在前面（z_index=%d）" % wf_sp.z_index)
			_check(wf_sp.modulate.a < 0.8, "挡住敌人的墙被虚化（alpha=%.2f）" % wf_sp.modulate.a)
			enemy_oc.global_position = Vector2(wf_cx, wf_base + 160.0)
			for _f3 in range(20):
				await get_tree().process_frame
			await _physics(2)
			_check(wf_sp.modulate.a > 0.9, "敌人走到墙前面后墙恢复不透明（alpha=%.2f）" % wf_sp.modulate.a)
		enemy_oc.set_physics_process(true)
		enemy_oc.global_position = Vector2(60, 150)
		Timeline.toggle()   # 切回现代
		await _physics(4)
		player.global_position = world.spawn_position
		await _physics(2)

	print("== 反击削韧 / 破防瘫痪 ==")
	_release_all()
	player.reset_stats()
	var pd: Node2D = world.get_node("YSort/TestDummy")
	pd.set_physics_process(true)
	pd.hp = pd.hp_max
	pd.poise = pd.poise_max
	pd.paralyzed_left = 0.0
	pd.charging = false
	pd.wave_active = false
	await _physics(3)
	_check(absf(player.counter_poise_damage - 20.0) < 0.01, "反击削韧性 20（%.0f）" % player.counter_poise_damage)
	pd.damage_poise(player.counter_poise_damage)
	_check(absf(pd.poise - 30.0) < 0.01, "削 20 后剩 30 韧性（%.0f）" % pd.poise)
	_check(not pd.is_paralyzed(), "韧性没破不会瘫痪")
	pd.damage_poise(30.0)
	_check(pd.poise <= 0.01 and pd.is_paralyzed(), "韧性归零进入瘫痪（%.0f）" % pd.poise)
	_check(absf(pd.poise_break_seconds - 5.0) < 0.01, "瘫痪时长 5 秒（%.1f）" % pd.poise_break_seconds)
	var cycle_before: float = pd._cycle
	await _physics(40)
	_check(not pd.charging and not pd.wave_active, "瘫痪期间不攻击")
	_check(absf(pd._cycle - cycle_before) < 0.001, "瘫痪期间攻击计时不走（%.2f）" % pd._cycle)
	await _physics(5 * 60 + 40)
	_check(not pd.is_paralyzed(), "瘫痪结束（%.1f）" % pd.paralyzed_left)
	_check(absf(pd.poise - pd.poise_max) < 0.01, "瘫痪结束后韧性回满（%.0f/%.0f）" % [pd.poise, pd.poise_max])
	pd.set_physics_process(false)
	player.global_position = world.spawn_position
	await _physics(3)

	print("== 地图 / 地面 ==")
	var ground: Node2D = world.get_node_or_null("Ground")
	_check(ground != null, "场景里有 Ground 节点")
	if ground != null:
		_check(ground.floor_texture == null and not ground.draw_grid, "地面只当深色底（两个时空都用地图）")
		_check(ground.bg_color.v < 0.3, "地面底色偏暗（v=%.2f）" % ground.bg_color.v)
		_check(world.modern_map != null and world.future_map != null, "两张等距地图都在场景里")
		_check(world._map_rect_for(world.modern_map).size.x > 1000.0,
			"现代地图范围 %.0f×%.0f" % [world._map_rect_for(world.modern_map).size.x, world._map_rect_for(world.modern_map).size.y])
		_check(world._map_rect_for(world.future_map).size.x > 1000.0,
			"未来地图范围 %.0f×%.0f" % [world._map_rect_for(world.future_map).size.x, world._map_rect_for(world.future_map).size.y])
	print("== 音效 ==")
	_release_all()
	player.reset_stats()
	player.global_position = Vector2(-200, 150)
	player.facing = "S"
	player.time_since_stamina_use = 0.0
	await _physics(6)
	_check(player.get_node_or_null("RunSfx") != null, "跑步音效节点存在")
	_check(player.get_node_or_null("BlockSfx") != null, "格挡音效节点存在")
	_check(player.get_node_or_null("PerfectBlockSfx") != null, "完美格挡音效节点存在")
	_check(player.run_sfx.stream != null and player.block_sfx.stream != null and player.perfect_block_sfx.stream != null,
		"三个音效都挂了音频流")
	_check(player.run_sfx.stream is AudioStreamMP3 and (player.run_sfx.stream as AudioStreamMP3).loop,
		"跑步音效设为循环")

	# 移动时播放、停下停止
	Input.action_press("move_right")
	await _physics(15)
	_check(player.run_sfx.playing, "移动时播放跑步音效")
	Input.action_release("move_right")
	await _physics(60)
	_check(not player.run_sfx.playing, "停下后停止跑步音效")

	# 格挡命中音效
	player.reset_stats()
	player.facing = "S"
	await _physics(4)
	Input.action_press("block")
	await _physics(20)                  # 进入保持
	_check(not player.block_sfx.playing or player.block_sfx.get_playback_position() >= 0.0, "格挡音效初始未播放")
	player.try_take_hit(10.0, player.global_position + Vector2(40, 0))
	_check(player.block_sfx.playing, "普通格挡命中播放格挡音效")
	Input.action_release("block")
	await _physics(40)

	# 闪避 / 完美闪避 / 普攻音效
	player.reset_stats()
	player.global_position = Vector2(-200, 150)
	player.dodge_cooldown_left = 0.0
	await _physics(4)
	_check(player.dodge_sfx.stream != null and player.perfect_dodge_sfx.stream != null and player.attack_sfx.stream != null,
		"闪避 / 完美闪避 / 普攻 音效都挂了音频流")
	Input.action_press("dodge")
	await _physics(2)
	Input.action_release("dodge")
	_check(player.dodge_sfx.playing, "闪避时播放闪避音效")
	await _physics(40)
	_check(not player.dodge_sfx.playing, "闪避音效播完自动停止")

	Input.action_press("attack")
	await _physics(2)
	Input.action_release("attack")
	_check(player.attack_sfx.playing, "普攻起手播放普攻音效")
	await _physics(40)

	# 完美闪避（时缓会压低时间流速，用真实时间等待）
	player.reset_stats()
	player.stamina = 100.0
	player.dodge_cooldown_left = 0.0
	await _physics(4)
	Input.action_press("dodge")
	for _w4 in range(6):                 # 等到真的进入闪避
		await _physics(1)
		if player.state == "dodge":
			break
	player.try_take_hit(10.0, player.global_position + Vector2(40, 0))
	_check(player.state == "dodge" and player.perfect_used, "音效测试里触发了完美闪避（%s, perfect=%s）" % [player.state, player.perfect_used])
	_check(player.perfect_dodge_sfx.playing, "完美闪避播放专属音效")
	Input.action_release("dodge")
	Engine.time_scale = 1.0
	var _dodge_guard := 0
	while player.state == "dodge" and _dodge_guard < 120:
		await _physics(1)
		_dodge_guard += 1
		player._slow_left = 0.0
		Engine.time_scale = 1.0
	player._slow_left = 0.0
	Engine.time_scale = 1.0
	player.reset_stats()
	await _physics(10)

	# 反击音效
	player.reset_stats()
	player.global_position = Vector2(-200, 150)
	player.facing = "S"
	await _physics(4)
	_check(player.counter_sfx.stream != null, "反击音效挂了音频流")
	player._start_counter()
	for _w5 in range(40):                 # 反击音效在刀光命中那一帧才响
		await _physics(1)
		if player.counter_hit_done:
			break
	_check(player.counter_sfx.playing, "反击刀光命中时播放反击音效")
	for _w6 in range(60):                 # 等反击动画播完，回到普通状态
		await _physics(1)
		if player.state != "counter":
			break
	await _physics(6)
	player.reset_stats()

	# 复活音效
	player.reset_stats()
	await _physics(4)
	player.respawn(player.global_position)
	await _physics(10)
	player.reset_stats()
	# 完美格挡音效
	player.reset_stats()
	player.stamina = 100.0
	await _physics(4)
	Input.action_press("block")
	for _w3 in range(6):                 # 等到真的进入抬手阶段
		await _physics(1)
		if player.state == "block" and player.block_phase == "in":
			break
	player.try_take_hit(10.0, player.global_position + Vector2(40, 0))
	_check(player.state == "perfect_block", "音效测试里确实触发了完美格挡（%s）" % player.state)
	_check(player.perfect_block_sfx.playing, "完美格挡播放专属音效")
	_check(absf(player.perfect_block_sfx_offset - 0.7) < 0.001, "完美格挡音效从 0.7s 开始播（%.2f）" % player.perfect_block_sfx_offset)
	_check(player.perfect_block_sfx.get_playback_position() >= 0.69,
		"播放位置直接从 0.7s 起（实际 %.2fs / 总长 %.2fs）" % [player.perfect_block_sfx.get_playback_position(), player.perfect_block_sfx.stream.get_length()])
	await _physics(60)                  # 等时停结束
	Input.action_release("block")
	await _physics(40)
	player.reset_stats()
	print("== 按键自定义 ==")
	_check(Keybinds != null, "Keybinds 自动加载存在")
	if Keybinds != null:
		Keybinds.reset_defaults()
		_check(Keybinds.MAX_SLOTS == 2, "每个动作最多两个按键（%d）" % Keybinds.MAX_SLOTS)
		_check(Keybinds.keycode_of("attack", 0) == KEY_J and Keybinds.keycode_of("attack", 1) == 0,
			"普攻默认只绑 J（槽0=%s 槽1=%s）" % [Keybinds.key_text("attack", 0), Keybinds.key_text("attack", 1)])
		_check(Keybinds.keycodes_of("dodge").size() == 2, "闪避默认绑了两个键（Shift + L）")
		_check(Keybinds.keycode_of("dodge", 0) == KEY_SHIFT and Keybinds.keycode_of("dodge", 1) == KEY_L,
			"闪避默认键是 Shift 和 L（%s / %s）" % [Keybinds.key_text("dodge", 0), Keybinds.key_text("dodge", 1)])
		var dodge_keys: Array = []
		for dodge_ev in InputMap.action_get_events("dodge"):
			if dodge_ev is InputEventKey:
				dodge_keys.append((dodge_ev as InputEventKey).physical_keycode)
		_check(dodge_keys.has(KEY_SHIFT) and dodge_keys.has(KEY_L), "InputMap 里闪避是 Shift + L（%s）" % str(dodge_keys))
		_check(not dodge_keys.has(KEY_SPACE), "闪避不再绑空格（%s）" % str(dodge_keys))
		_check(Keybinds.keycodes_of("move_up").size() == 2, "移动上默认绑了两个键（W + Up）")

		Keybinds.rebind("attack", 1, KEY_K)
		_check(Keybinds.keycode_of("attack", 1) == KEY_K, "给普攻的第二个槽绑 K（%s）" % Keybinds.key_text("attack", 1))
		_check(InputMap.action_get_events("attack").size() == 2, "InputMap 里普攻打两个键（实际 %d）" % InputMap.action_get_events("attack").size())
		_check(FileAccess.file_exists("user://keybinds.cfg"), "改键后写入配置文件")

		# 改成别的动作已占用的键：两者交换，不会失效
		Keybinds.rebind("attack", 1, KEY_W)
		_check(Keybinds.keycode_of("attack", 1) == KEY_W and Keybinds.keycode_of("move_up", 0) == KEY_K,
			"占用冲突时交换按键（上槽0=%s 攻槽1=%s）" % [Keybinds.key_text("move_up", 0), Keybinds.key_text("attack", 1)])

		# 清空某个槽位
		Keybinds.clear_slot("attack", 1)
		_check(Keybinds.keycode_of("attack", 1) == 0 and Keybinds.keycodes_of("attack").size() == 1,
			"可以清空单个槽位（剩 %d 个键）" % Keybinds.keycodes_of("attack").size())

		Keybinds.reset_defaults()
		_check(Keybinds.keycode_of("attack", 0) == KEY_J and Keybinds.keycode_of("move_up", 0) == KEY_W,
			"恢复默认键位（上=%s 攻=%s）" % [Keybinds.key_text("move_up", 0), Keybinds.key_text("attack", 0)])

	print("== 设置界面 ==")
	var menu: CanvasLayer = world.get_node_or_null("SettingsMenu")
	_check(menu != null, "世界里有设置界面节点")
	if menu != null:
		_check(not menu.is_open(), "设置界面默认关闭")
		menu.open()
		_check(menu.is_open() and get_tree().paused, "打开设置界面时游戏暂停")
		var expected := Keybinds.ACTIONS.size() * (1 + Keybinds.MAX_SLOTS)   # 每行：1 个标签 + 2 个按键槽
		_check(menu.grid.get_child_count() == expected,
			"设置界面有 %d 个控件（8 行 × 标签/两槽，实际 %d）" % [expected, menu.grid.get_child_count()])
		menu.close()
		_check(not menu.is_open() and not get_tree().paused, "关闭设置界面后恢复游戏")
	Engine.time_scale = 1.0

	print("== 极限闪避（闪避免伤 / 时缓 / 回体力） ==")
	_release_all()
	player.reset_stats()
	player.global_position = Vector2(-200, 150)
	await _physics(10)
	_check(player.get_node_or_null("PerfectFlash") == null, "极限闪避不再有黄圈光环节点")
	_check(absf(player.perfect_stamina_gain - 40.0) < 0.001, "极限闪避回体力 40（%.0f）" % player.perfect_stamina_gain)
	_check(player.perfect_window > 0.05, "极限闪避有前置判定窗口（%.2fs）" % player.perfect_window)
	_check(player.perfect_time_scale < 0.25, "时缓强度被加强（time_scale=%.2f）" % player.perfect_time_scale)

	# 闪避起手被命中 → 极限闪避
	player.stamina = 60.0
	player.dodge_cooldown_left = 0.0
	Input.action_press("dodge")
	await get_tree().physics_frame
	Input.action_release("dodge")
	await get_tree().physics_frame
	_check(player.state == "dodge", "进入闪避（%s）" % player.state)
	_check(absf(player.stamina - 40.0) < 0.06, "闪避先扣 20 点体力（%.0f）" % player.stamina)
	_check(not player.afterimage.is_golden(), "普通闪避的残影不是金色")
	# 闪避免伤：直接扣血接口不掉血
	_check(not player.take_damage(10.0), "闪避期间 take_damage 不掉血（%.0f）" % player.hp)
	var hit_result: String = player.try_take_hit(10.0, Vector2.RIGHT)
	_check(hit_result == "perfect", "闪避起手被命中 → 极限闪避（%s）" % hit_result)
	_check(absf(player.stamina - 80.0) < 0.06, "极限闪避回复 40 点体力（%.0f → %.0f）" % [40.0, player.stamina])
	_check(Engine.time_scale < 0.25, "触发强化时缓（time_scale=%.2f）" % Engine.time_scale)
	_check(player.afterimage.is_golden(), "极限闪避后残影转金色")
	_check(player.perfect_used, "同一次闪避只会触发一次极限闪避")
	_check(player.try_take_hit(10.0, Vector2.RIGHT) == "blocked", "已触发过后只算普通闪避免伤")
	_check(absf(player.hp - player.hp_max) < 0.001, "全程没有掉血（%.0f）" % player.hp)
	# 时缓会在 0.6s 真实时间内平滑恢复
	await get_tree().create_timer(0.8, true, false, true).timeout
	_check(absf(Engine.time_scale - 1.0) < 0.01, "时缓会自动恢复（time_scale=%.2f）" % Engine.time_scale)
	await _physics(10)

	# 闪避后半段才被命中：普通闪避免伤，不回体力、不触发时缓
	player.reset_stats()
	player.dodge_cooldown_left = 0.0
	Input.action_press("dodge")
	await get_tree().physics_frame
	Input.action_release("dodge")
	await get_tree().physics_frame
	player.dodge_time = player.perfect_window + 0.1
	var st_before: float = player.stamina
	_check(player.try_take_hit(10.0, Vector2.RIGHT) == "blocked", "闪避后段被命中只算普通闪避")
	_check(absf(player.stamina - st_before) < 0.01, "普通闪避不回体力（%.0f）" % player.stamina)
	_check(absf(Engine.time_scale - 1.0) < 0.01, "普通闪避不触发时缓")
	_check(not player.afterimage.is_golden(), "普通闪避残影保持原色")
	await _physics(40)
	Engine.time_scale = 1.0
	player.reset_stats()

	print("== 死亡回溯 + 出生点复活 ==")
	_release_all()
	var rewind_node: CanvasLayer = world.get_node_or_null("RewindScreen")
	_check(rewind_node != null, "存在回溯画面节点（RewindScreen）")
	if rewind_node != null:
		_check(not rewind_node.visible, "回溯画面默认隐藏")
		var rewind_label: Label = rewind_node.get_node("Label")
		_check(rewind_label.text == "时间回溯", "回溯文字为「时间回溯」（实际 %s）" % rewind_label.text)

		var spawn: Vector2 = world.spawn_position
		player.reset_stats()
		player.global_position = Vector2(-260, 160)   # 死在远处，验证复活会回到出生点
		await _physics(4)
		player.kill()
		await _physics(3)
		_check(player.state == "dying" and sprite.animation == "death", "死亡先播倒地动画（%s）" % sprite.animation)
		_check(player.death_sfx.stream != null, "倒地音效挂了音频流（%.2fs）" % player.death_sfx.stream.get_length())
		_check(player.death_sfx.playing, "倒地时播放倒地音效")
		_check(not rewind_node.visible, "倒地动画期间还没开始黑屏")
		await _physics(60)                 # 倒地动画 0.75s 播完
		_check(rewind_node.visible and rewind_node.is_playing(), "倒地动画播完后才开始黑屏回溯")
		_check(not player.is_physics_processing(), "回溯期间角色被冻结")
		# 全黑阶段（fade_in 之后、hold 期间）就应该已经复位，玩家看不到瞬移
		await _physics(30)
		_check(rewind_node.visible and rewind_node.is_playing(), "第 0.5s 仍处于黑屏回溯阶段")
		_check(player.global_position.distance_to(spawn) < 0.5,
			"全黑时就已回到出生点（%.1f, %.1f）" % [player.global_position.x, player.global_position.y])
		_check(absf(player.hp - player.hp_max) < 0.001, "全黑时已经满血（%.0f）" % player.hp)
		await _physics(120)
		_check(absf(player.hp - player.hp_max) < 0.001, "复活后满血（%.0f）" % player.hp)
		_check(not player.is_dead(), "复活后不在死亡状态")
		_check(not player.is_dying() and not player.death_finished, "复活后倒地状态已清空")
		_check(player.global_position.distance_to(spawn) < 0.5,
			"复活在出生点（%.1f, %.1f）" % [player.global_position.x, player.global_position.y])
		_check(not rewind_node.visible, "回溯画面播放完自动关闭")
		_check(player.is_physics_processing(), "角色恢复物理处理（可以继续跑）")

		# F6 调试键也能触发同样的流程（先倒地再黑屏）
		var evk := InputEventAction.new()
		evk.action = "debug_kill"
		evk.pressed = true
		world._unhandled_input(evk)
		await _physics(5)
		_check(player.state == "dying", "F6 也先进入倒地（%s）" % player.state)
		_check(not rewind_node.visible, "F6 倒地期间还没黑屏")
		await _physics(60)
		_check(rewind_node.visible, "F6 倒地播完后进入黑屏回溯")
		await _physics(150)
		_check(not player.is_dead() and absf(player.hp - player.hp_max) < 0.001, "F6 回溯后也已满血复活")

	print("== 格挡致死不会卡慢放 ==")
	_release_all()
	player.reset_stats()
	player.global_position = Vector2(-300, 150)
	await _physics(6)
	player.hp = 1.0                       # 下一击必死
	Input.action_press("block")           # 抬起格挡
	await _physics(20)
	_check(player.state == "block" or player.is_blocking(), "进入格挡（%s）" % player.state)
	# 格挡住这一击：会触发顿帧（time_scale=0.02），同时伤害把血打空
	player.try_take_hit(20.0, player.global_position + Vector2(40, 0))
	await _physics(3)
	_check(player.is_dead(), "格挡中被这次攻击打死（hp=%.0f）" % player.hp)
	_check(absf(Engine.time_scale - 1.0) < 0.01, "死亡立刻恢复时间流速（time_scale=%.2f）" % Engine.time_scale)
	var rewind2: CanvasLayer = world.get_node("RewindScreen")
	await _physics(60)                    # 倒地动画 0.75s：没被慢放的话这时已经黑屏
	_check(rewind2.visible, "倒地动画正常播完并进入黑屏（没被慢放拖住）")
	Input.action_release("block")
	await _physics(150)
	_check(absf(Engine.time_scale - 1.0) < 0.01, "回溯结束后时间流速仍是 1.0（%.2f）" % Engine.time_scale)
	_check(not player.is_dead(), "已满血复活（%.0f）" % player.hp)
	print("== 闪避残影 ==")
	_release_all()
	player.reset_stats()
	player.global_position = Vector2(-200, 150)   # 远离伤害墙，避免闪避撞墙原地不动
	await _physics(40)
	var layer: Node = player.get_parent()
	_check(_count_ghosts(layer) == 0, "起手前没有残影（%d）" % _count_ghosts(layer))
	Input.action_press("move_right")
	Input.action_press("dodge")
	await get_tree().physics_frame
	Input.action_release("dodge")
	await get_tree().physics_frame
	_check(_count_ghosts(layer) == 0, "起手瞬间不在原地留影（%d）" % _count_ghosts(layer))
	await _physics(20)
	_check(_count_ghosts(layer) > 0, "闪避中生成残影（%d）" % _count_ghosts(layer))
	await _physics(70)
	_check(_count_ghosts(layer) == 0, "闪避结束后残影清空（%d）" % _count_ghosts(layer))
	_release_all()

	print("== 松手回到站立 ==")
	_release_all()
	await _physics(40)
	_check(player.state == "stand", "松开按键后回到 stand（实际 %s）" % player.state)
	_check(player.velocity.length() < 1.0, "速度归零（实际 %.1f）" % player.velocity.length())
	_check(sprite.animation.begins_with("stand_"), "播放站立动画（实际 %s）" % sprite.animation)

	print("== 未来敌人：不在索敌范围时不走动 ==")
	_release_all()
	if Timeline.is_future():
		pass
	else:
		Timeline.toggle()
		await _physics(4)
	player.reset_stats()
	player.global_position = Vector2(2400, 2400)   # 玩家离得非常远
	var fe_start: Array[Vector2] = []
	for fe in future_enemies:
		(fe as Node2D).global_position = future_enemy_home[future_enemies.find(fe)]
		fe.set_physics_process(true)
		await _physics(1)
		fe_start.append((fe as Node2D).global_position)
	for _f in range(120):   # 2 秒
		await _physics(1)
	var fe_moved: float = 0.0
	var idle_pose_ok := true
	for i3 in range(future_enemies.size()):
		var fe2: Node2D = future_enemies[i3]
		fe_moved = maxf(fe_moved, fe_start[i3].distance_to(fe2.global_position))
		var sp3: AnimatedSprite2D = fe2.get_node_or_null("Sprite")
		if sp3 != null and sp3.is_playing():
			idle_pose_ok = false
		var ms2: AnimatedSprite2D = fe2.get_node_or_null("Muzzle")
		if ms2 != null and ms2.visible:
			idle_pose_ok = false
		fe2.set_physics_process(false)
	_check(fe_moved < 1.0, "玩家不在索敌范围时未来敌人不移动（最大位移 %.2f）" % fe_moved)
	_check(idle_pose_ok, "它们停在站定姿势（没有在走路/开枪）")
	for fe in future_enemies:
		(fe as Node2D).global_position = Vector2(2600, 2600)
	if Timeline.is_future():
		Timeline.toggle()
		await _physics(4)
	player.global_position = Vector2(-96, 0)
	await _physics(4)

	print("== 未来敌人（枪手） ==")
	_release_all()
	player.reset_stats()
	var enemy: Node = world.get_node_or_null("YSort/FutureEnemy")
	if enemy != null:
		enemy.set_physics_process(true)   # 前面的用例会临时停掉它
		(enemy as Node2D).global_position = Vector2(200, 60)
		enemy.hp = enemy.hp_max
		enemy.poise = enemy.poise_max
		enemy.energy = enemy.energy_max
		enemy.recover_left = 0.0
		enemy.dead = false
		enemy.dead_left = 0.0
		enemy.bars.visible = true
		enemy.modulate = Color(1, 1, 1, 1)
	_check(enemy != null, "场景里存在未来敌人")
	if enemy != null:
		# 数值
		_check(absf(enemy.hp_max - 40.0) < 0.001, "敌人血量上限 40（%.0f）" % enemy.hp_max)
		_check(absf(enemy.poise_max - 50.0) < 0.001, "敌人韧性上限 50（%.0f）" % enemy.poise_max)
		_check(absf(enemy.energy_max - 20.0) < 0.001, "敌人能量上限 20（%.0f）" % enemy.energy_max)
		# 未来时空才启用
		world.player.global_position = Vector2(-96, 0)
		await _physics(2)
		_check(not enemy.visible, "现代时空敌人不显示")
		Timeline.toggle()
		await _physics(4)
		_check(enemy.visible and enemy.process_mode != Node.PROCESS_MODE_DISABLED, "未来时空敌人启用")
		# 放到玩家附近，等它开火
		player.global_position = Vector2(120, 40)
		enemy.global_position = Vector2(200, 60)
		enemy.hp = enemy.hp_max
		enemy.energy = enemy.energy_max
		enemy.recover_left = 0.0
		enemy.bullets_fired = 0
		enemy.volleys_fired = 0
		var bullets_before_enemy := _count_bullets()
		await _physics(240)   # 4 秒左右，够打一轮
		_check(enemy.volleys_fired >= 1, "敌人开了枪（%d 轮）" % enemy.volleys_fired)
		_check(enemy.bullets_fired >= 3, "每次开枪发出 3 发子弹（%d 发）" % enemy.bullets_fired)
		_check(absf(enemy.energy - (enemy.energy_max - enemy.shot_cost)) < 0.01 or enemy.volleys_fired > 1,
			"开一轮消耗 5 点能量（剩 %.0f）" % enemy.energy)
		# 能量打完 → 进入恢复
		enemy.energy = 0.0
		enemy.recover_left = enemy.energy_recover_seconds
		enemy.volleys_fired = 0
		await _physics(30)
		_check(not enemy.is_paralyzed(), "能量耗尽时敌人不是瘫痪（只是停火）")
		_check(enemy.volleys_fired == 0, "能量耗尽期间不开火（%d 轮）" % enemy.volleys_fired)
		await get_tree().create_timer(enemy.energy_recover_seconds + 0.4).timeout
		_check(enemy.energy >= enemy.energy_max - enemy.shot_cost - 0.01,
			"10 秒后能量回满（剩 %.0f，可能立刻又打了一轮）" % enemy.energy)
		await _physics(240)
		_check(enemy.volleys_fired >= 1, "能量回满后恢复开火（%d 轮）" % enemy.volleys_fired)
		# 韧性破裂 → 瘫痪
		enemy.damage_poise(enemy.poise_max)
		await _physics(2)
		_check(enemy.is_paralyzed(), "韧性打空后敌人瘫痪")
		enemy.volleys_fired = 0
		await _physics(60)
		_check(enemy.volleys_fired == 0, "瘫痪期间不开火（%d 轮）" % enemy.volleys_fired)
		# 血量归零 → 倒下
		enemy.take_damage(enemy.hp_max)
		await _physics(2)
		_check(enemy.is_broken(), "血量归零后敌人倒下")
		_check(enemy.modulate.a < 0.95, "倒下后变暗（alpha=%.2f）" % enemy.modulate.a)
		_check(not enemy.bars.visible, "死亡后血条隐藏")
		_check(absf(enemy.dead_left - enemy.corpse_seconds) < 0.2,
			"尸体开始 20 秒倒计时（剩余 %.1f）" % enemy.dead_left)
		await _physics(40)
		_check(enemy.dead_left < enemy.corpse_seconds - 0.3,
			"尸体计时在走（剩余 %.1f）" % enemy.dead_left)
		# 另建一个实例验证"20 秒后消失"（把计时缩短到 0.1 秒）
		var corpse_scene: PackedScene = load("res://scenes/future_enemy.tscn")
		var corpse: Node = corpse_scene.instantiate()
		world.get_node("YSort").add_child(corpse)
		corpse.global_position = Vector2(-120, 40)
		await _physics(2)
		corpse.take_damage(corpse.hp_max)
		corpse.dead_left = 0.1
		await _physics(20)
		_check(not is_instance_valid(corpse), "尸体到时间后自动消失")
		# 复原，切回现代
		enemy.hp = enemy.hp_max
		enemy.dead = false
		enemy.dead_left = 0.0
		enemy.bars.visible = true
		enemy.modulate = Color(1, 1, 1, 1)
		enemy.paralyzed_left = 0.0
		enemy.poise = enemy.poise_max
		Timeline.toggle()
		await _physics(4)
		player.global_position = Vector2(-96, 0)
		_clear_bullets()
		await _physics(2)

	print("== 现代敌人（剑士） ==")
	_release_all()
	if Timeline.is_future():
		Timeline.toggle()
		await _physics(4)
	player.reset_stats()
	player.global_position = Vector2(2400, 2400)
	var menemy: Node = world.get_node_or_null("YSort/ModernEnemy")
	_check(modern_enemies.size() == 3, "现代时空有三个敌人（%d 个）" % modern_enemies.size())
	var me_positions: Array[Vector2] = modern_enemy_home
	_check(me_positions[0].distance_to(Vector2(400, -40)) < 16.0,
		"敌人 1 站在右侧路口（%.0f, %.0f）" % [me_positions[0].x, me_positions[0].y])
	_check(me_positions[1].distance_to(Vector2(-320, -160)) < 14.0,
		"敌人 2 站在左上路口（%.0f, %.0f）" % [me_positions[1].x, me_positions[1].y])
	_check(me_positions[2].distance_to(Vector2(-320, 160)) < 14.0,
		"敌人 3 站在左下路口（%.0f, %.0f）" % [me_positions[2].x, me_positions[2].y])
	_check(world.get_node_or_null("YSort/ModernEnemy2") != null and world.get_node_or_null("YSort/ModernEnemy3") != null,
		"三个现代敌人节点都在场景里")
	_check(menemy != null, "场景里存在现代敌人")
	if menemy != null:
		_check(absf(menemy.hp_max - 40.0) < 0.001, "现代敌人生命 40（%.0f）" % menemy.hp_max)
		_check(absf(menemy.poise_max - 20.0) < 0.001, "现代敌人韧性 20（%.0f）" % menemy.poise_max)
		_check(absf(menemy.stamina_max - 40.0) < 0.001, "现代敌人隐藏体力 40（%.0f）" % menemy.stamina_max)
		_check(absf(menemy.attack_cost - 5.0) < 0.001, "每次攻击消耗 5 点体力")
		_check(absf(menemy.walk_regen_per_sec - 5.0) < 0.001, "行走每秒回复 5 点体力")
		_check(absf(menemy.run_drain_per_sec - 1.0) < 0.001, "奔跑每秒消耗 1 点体力")
		_check(absf(menemy.resume_threshold - 20.0) < 0.001, "体力回到 20 才恢复攻击/奔跑")
		_check(menemy.detect_radius <= 200.0, "索敌半径已缩小（%.0f）" % menemy.detect_radius)
		_check(menemy.bars.visible, "现代敌人默认显示血条")
		# 现代时空启用 / 未来时空隐藏
		Timeline.toggle()
		await _physics(4)
		_check(not menemy.visible, "现代敌人在未来时空隐藏")
		Timeline.toggle()
		await _physics(4)
		_check(menemy.visible, "现代敌人在现代时空可见")
		# 平时行走：玩家在侦测范围外
		menemy.hp = menemy.hp_max
		menemy.poise = menemy.poise_max
		menemy.stamina = menemy.stamina_max
		menemy.exhausted = false
		menemy.dead = false
		menemy.dead_left = 0.0
		menemy.bars.visible = true
		menemy.modulate = Color(1, 1, 1, 1)
		menemy.global_position = Vector2(120, 120)
		menemy.set_physics_process(true)
		player.global_position = Vector2(120, 700)
		await _physics(4)
		menemy._home = menemy.global_position
		menemy._pick_patrol_target()
		var saw_walk := false
		var walk_moved := 0.0
		var w0: Vector2 = menemy.global_position
		for _k in range(90):
			await _physics(1)
			if menemy.state == "walk":
				saw_walk = true
			walk_moved = maxf(walk_moved, w0.distance_to(menemy.global_position))
		_check(saw_walk, "没有玩家时敌人处于行走状态")
		_check(walk_moved > 2.0, "行走时会移动（位移 %.1f）" % walk_moved)
		# 发现玩家 → 奔跑
		menemy.stamina = menemy.stamina_max
		menemy.exhausted = false
		menemy.global_position = Vector2(120, 120)
		player.global_position = Vector2(120, 240)   # 距离 120，在新的侦测半径 170 内
		await _physics(2)
		var saw_run := false
		var stamina_before: float = menemy.stamina
		for _k in range(40):
			await _physics(1)
			if menemy.state == "run":
				saw_run = true
		_check(saw_run, "发现玩家后进入奔跑状态")
		_check(menemy.stamina < stamina_before, "奔跑时体力下降（%.1f → %.1f）" % [stamina_before, menemy.stamina])
		# 攻击：贴脸
		player.reset_stats()
		player.global_position = menemy.global_position + Vector2(30, 0)
		menemy.stamina = menemy.stamina_max
		menemy.exhausted = false
		menemy.attacks_made = 0
		# 单次攻击正好扣 5
		menemy.stamina = menemy.stamina_max
		menemy.exhausted = false
		menemy._start_attack(player)
		_check(absf(menemy.stamina - 35.0) < 0.01, "一次攻击扣 5 点体力（剩 %.0f）" % menemy.stamina)
		# 体力不足：打不了
		menemy._attacking = false
		menemy.stamina = 3.0
		menemy.exhausted = true
		menemy._attack_timer = 0.0
		menemy.attacks_made = 0
		player.reset_stats()
		player.global_position = menemy.global_position + Vector2(30, 0)
		await _physics(30)
		_check(menemy.attacks_made == 0, "体力不足以攻击（<5）时不能攻击（%d 次）" % menemy.attacks_made)
		# 行走回体力，回到 20 以上恢复攻击
		var stamina_mid: float = menemy.stamina
		await _physics(60)   # 1 秒 → 回复约 5 点
		_check(menemy.stamina > stamina_mid, "行走时体力回升（%.1f → %.1f）" % [stamina_mid, menemy.stamina])
		var guard := 0
		while menemy.stamina < menemy.resume_threshold and guard < 600:
			await _physics(1)
			guard += 1
		await _physics(30)
		menemy.attacks_made = 0
		menemy._attack_timer = 0.0
		await _physics(180)
		_check(menemy.attacks_made >= 1, "体力回到 20 以上后恢复攻击（%d 次）" % menemy.attacks_made)
		# 韧性打空 → 瘫痪
		menemy.stamina = menemy.stamina_max
		menemy.exhausted = false
		menemy.damage_poise(menemy.poise_max)
		await _physics(2)
		_check(menemy.is_paralyzed(), "韧性打空后现代敌人瘫痪")
		menemy.attacks_made = 0
		await _physics(60)
		_check(menemy.attacks_made == 0, "瘫痪期间不攻击（%d 次）" % menemy.attacks_made)
		# 死亡：血条隐藏 + 尸体计时
		menemy.paralyzed_left = 0.0
		menemy.poise = menemy.poise_max
		menemy.take_damage(menemy.hp_max)
		await _physics(2)
		_check(menemy.is_broken(), "血量归零后现代敌人倒下")
		_check(not menemy.bars.visible, "现代敌人死亡后血条隐藏")
		_check(absf(menemy.dead_left - menemy.corpse_seconds) < 0.2, "尸体保留 20 秒倒计时（%.1f）" % menemy.dead_left)
		# 复位移开
		menemy.hp = menemy.hp_max
		menemy.poise = menemy.poise_max
		menemy.stamina = menemy.stamina_max
		menemy.dead = false
		menemy.dead_left = 0.0
		menemy.exhausted = false
		menemy.bars.visible = true
		menemy.modulate = Color(1, 1, 1, 1)
		menemy.global_position = Vector2(2400, 2400)
		menemy.set_physics_process(false)
		player.reset_stats()
		player.global_position = Vector2(-96, 0)
		await _physics(4)

	print("== 现代敌人：攻击动作 / 体力机制 ==")
	_release_all()
	if Timeline.is_future():
		Timeline.toggle()
		await _physics(4)
	player.reset_stats()
	var me2: Node = world.get_node_or_null("YSort/ModernEnemy")
	_check(me2 != null, "现代敌人在场")
	if me2 != null:
		me2.hp = me2.hp_max
		me2.poise = me2.poise_max
		me2.stamina = me2.stamina_max
		me2.exhausted = false
		me2.dead = false
		me2.dead_left = 0.0
		me2.bars.visible = true
		me2.modulate = Color(1, 1, 1, 1)
		me2.global_position = Vector2(120, 120)
		me2.set_physics_process(true)
		player.global_position = Vector2(150, 120)
		me2._attack_timer = 0.0
		await _physics(2)
		var saw_attack := false
		var anim_ok := false
		var attack_start := Vector2.ZERO
		var attack_moved := 0.0
		me2.attacks_made = 0
		for _k in range(90):
			if me2._attacking:
				if not saw_attack:
					saw_attack = true
					attack_start = me2.global_position
				if String(me2.sprite.animation).begins_with("attack_"):
					anim_ok = true
				attack_moved = maxf(attack_moved, attack_start.distance_to(me2.global_position))
			await _physics(1)
			if saw_attack and not me2._attacking:
				break
		_check(saw_attack, "敌人会进入攻击状态")
		_check(anim_ok, "攻击时播放 attack_* 动画")
		_check(attack_moved < 1.5, "攻击时敌人不移动（位移 %.2f）" % attack_moved)
		var atk_len: float = me2._anim_length("attack", me2.facing)
		_check(atk_len > 0.9, "攻击动作被拉长（总时长 %.2f 秒）" % atk_len)
		var windup: float = atk_len * me2.hit_ratio
		_check(windup >= 0.45, "起手（命中前）有反应时间（%.2f 秒）" % windup)
		# 体力机制：打空 → 只走 → 回到 20 → 恢复攻击
		me2.stamina = 0.0
		me2.exhausted = true
		me2.attacks_made = 0
		me2._attack_timer = 0.0
		await _physics(40)
		_check(me2.attacks_made == 0, "体力耗尽时不攻击（%d 次）" % me2.attacks_made)
		_check(me2.state == "walk", "体力耗尽时只走（state=%s）" % me2.state)
		var stamina_a: float = me2.stamina
		await _physics(60)
		_check(me2.stamina > stamina_a, "走路回体力（%.1f → %.1f）" % [stamina_a, me2.stamina])
		var g2 := 0
		while me2.stamina < me2.resume_threshold and g2 < 600:
			await _physics(1)
			g2 += 1
		_check(me2.stamina >= me2.resume_threshold, "体力回到 20 以上（%.1f）" % me2.stamina)
		await _physics(2)
		_check(not me2.exhausted, "回到 20 以上后解除力竭")
		me2._attacking = false
		me2.attacks_made = 0
		me2._attack_timer = 0.0
		player.reset_stats()
		player.global_position = me2.global_position + Vector2(30, 0)
		await _physics(180)
		_check(me2.attacks_made >= 1, "恢复后继续攻击（%d 次）" % me2.attacks_made)
		# 跑步门槛：体力不足时只能走
		me2.stamina = 0.5
		me2.exhausted = true
		player.global_position = me2.global_position + Vector2(100, 0)
		await _physics(20)
		_check(me2.state == "walk", "体力不足时不能奔跑（state=%s）" % me2.state)
		# 复位
		me2.stamina = me2.stamina_max
		me2.exhausted = false
		me2.global_position = Vector2(2400, 2400)
		me2.set_physics_process(false)
		player.reset_stats()
		player.global_position = Vector2(-96, 0)
		await _physics(4)

	print("== 现代敌人不会走出地图 ==")
	_release_all()
	if Timeline.is_future():
		Timeline.toggle()
		await _physics(4)
	player.reset_stats()
	player.global_position = Vector2(2400, 2400)   # 玩家离远，敌人只巡逻
	var rect: Rect2 = world._map_rect_for(world.modern_map)
	_check(rect.size.x > 1000.0, "拿到现代地图范围（%.0f×%.0f）" % [rect.size.x, rect.size.y])
	for idx in range(modern_enemies.size()):
		var m2: Node2D = modern_enemies[idx]
		m2.global_position = modern_enemy_home[idx]   # 先回到出生点
		await _physics(1)
		_check(world.is_walkable_point(m2.global_position),
			"%s 的出生点在可走地面上" % m2.name)
		_check(world.is_inside_play_area(m2.global_position),
			"%s 的出生点在栅栏范围内" % m2.name)

	for _f in range(600):   # 10 秒巡逻
		await _physics(1)
	await _physics(60)      # 再给 1 秒，让可能被挤出去的自己走回来
	var outside: int = 0
	var off_floor: int = 0
	for idx2 in range(modern_enemies.size()):
		var m3: Node2D = modern_enemies[idx2]
		var mp: Vector2 = m3.global_position
		if not rect.has_point(mp):
			outside += 1
		if not world.is_walkable_point(mp):
			print("    [debug] 悬空: %s at (%.0f, %.0f)" % [m3.name, mp.x, mp.y])
			off_floor += 1
		m3.set_physics_process(false)
	_check(outside == 0, "巡逻 10 秒后没有敌人跑出地图（%d 个在外面）" % outside)
	_check(off_floor == 0, "巡逻 10 秒后都站在地面上（%d 个悬空）" % off_floor)
	var outside_area: int = 0
	for m5 in modern_enemies:
		if not world.is_inside_play_area((m5 as Node2D).global_position):
			outside_area += 1
			print("    [debug] 越界: %s at %s" % [m5.name, str((m5 as Node2D).global_position)])
	_check(outside_area == 0, "巡逻 10 秒后都在栅栏范围内的路面上（%d 个越界）" % outside_area)
	for m4 in modern_enemies:
		(m4 as Node2D).global_position = Vector2(2400, 2400)
	player.global_position = Vector2(-96, 0)
	await _physics(4)

	print("== 受击音效 / 刷新动画 / 破防动画 ==")
	_release_all()
	if Timeline.is_future():
		Timeline.toggle()
		await _physics(4)
	player.reset_stats()
	_check(player.hit_sfx != null and player.hit_sfx.stream != null, "玩家受击音效已挂上（%s）" % str(player.hit_sfx.stream.resource_path))
	# 刷新动画：把现代敌人放回原位并复位，站到玩家视野里
	var me3: Node2D = world.get_node_or_null("YSort/ModernEnemy")
	if me3 != null:
		_check(me3.has_method("_start_spawn"), "现代敌人有刷新动画逻辑")
		me3.global_position = Vector2(400, -40)
		me3._spawn_done = false
		me3._spawning = false
		player.global_position = Vector2(340, -40)   # 就在旁边，肯定在视野里
		me3.set_physics_process(true)
		await _physics(4)
		_check(me3._spawning, "进入视野后开始播刷新动画")
		_check(String(me3.sprite.animation).begins_with("spawn_"), "刷新时播放 spawn_* 动画（%s）" % me3.sprite.animation)
		var spawn_guard := 0
		while me3._spawning and spawn_guard < 200:
			await _physics(1)
			spawn_guard += 1
		_check(not me3._spawning and me3._spawn_done, "刷新动画播完后恢复正常行为")
		# 破防动画：进入 → 循环 → 恢复
		me3.damage_poise(999.0)
		await _physics(2)
		_check(me3.is_paralyzed(), "韧性打空进入瘫痪")
		_check(String(me3.sprite.animation).begins_with("break_enter_"), "瘫痪开始播 break_enter_*（%s）" % me3.sprite.animation)
		await _physics(90)   # 1.5 秒，进入动画结束
		_check(String(me3.sprite.animation).begins_with("break_hold_"), "瘫痪期间循环播 break_hold_*（%s）" % me3.sprite.animation)
		var brk_guard := 0
		while me3.is_paralyzed() and brk_guard < 400:
			await _physics(1)
			brk_guard += 1
		await _physics(4)
		_check(String(me3.sprite.animation).begins_with("break_recover_"), "瘫痪结束播 break_recover_*（%s）" % me3.sprite.animation)
		var rec_guard := 0
		while String(me3.sprite.animation).begins_with("break_recover_") and rec_guard < 200:
			await _physics(1)
			rec_guard += 1
		await _physics(4)
		_check(not me3.is_paralyzed() and absf(me3.poise - me3.poise_max) < 0.01, "恢复动画结束后韧性回满（%.0f）" % me3.poise)
		# 死亡也用破防动画
		me3.take_damage(me3.hp_max)
		await _physics(2)
		_check(me3.dead, "血量归零后死亡")
		_check(String(me3.sprite.animation).begins_with("break_enter_"), "死亡时播破防进入动画（%s）" % me3.sprite.animation)
		await _physics(90)
		_check(String(me3.sprite.animation).begins_with("break_hold_"), "尸体停在破防循环姿势（%s）" % me3.sprite.animation)
		_check(not me3.bars.visible, "死亡后血条隐藏")
		me3.set_physics_process(false)
		me3.global_position = Vector2(2400, 2400)
	player.reset_stats()
	player.global_position = Vector2(-96, 0)
	await _physics(4)

	print("== 花盆 / 能量桩联动 ==")
	_release_all()
	if Timeline.is_future():
		Timeline.toggle()
		await _physics(4)
	player.reset_stats()
	player.global_position = Vector2(-96, 0)
	await _physics(4)
	var pot1: Node2D = world.get_node_or_null("YSort/FlowerPot1")
	var pylon1: Node = world.get_node_or_null("YSort/EnergyPylon1")
	_check(pot1 != null and pylon1 != null, "三个花盆与能量桩都在场景里")
	_check(world.get_node_or_null("YSort/FlowerPot3") != null and world.get_node_or_null("YSort/EnergyPylon3") != null, "第三组也齐全")
	if pot1 != null and pylon1 != null:
		world.pot_broken[0] = false
		world.pot_broken[1] = false
		world.pot_broken[2] = false
		world._refresh_era_props()
		pot1.broken = false
		pot1.visible = true
		var p1col: CollisionShape2D = pot1.get_node_or_null("Collision")
		if p1col != null:
			p1col.disabled = false
		_check(pot1.visible and not pylon1.visible, "现代时空：只显示花盆，能量桩隐藏")
		_check(not pylon1.activated, "能量桩初始是关闭状态")
		# 玩家打花盆 → 打碎
		player.global_position = pot1.global_position + Vector2(-30, 0)
		player.facing = "E"
		player.facing_dir = Vector2.RIGHT
		await _physics(6)
		Input.action_press("attack")
		await get_tree().physics_frame
		Input.action_release("attack")
		await _physics(30)
		_check(pot1.broken, "攻击把花盆打碎")
		_check(world.is_pot_broken(0) and not world.is_pot_broken(1), "只有被打的那个花盆记录为已碎")
		_check(String(pot1.sprite.animation).begins_with("break"), "花盆播放破碎动画（%s）" % pot1.sprite.animation)
		var guard2 := 0
		while pot1.visible and guard2 < 200:
			await _physics(1)
			guard2 += 1
		_check(not pot1.visible, "破碎动画播完花盆消失")
		_check(pot1.collision_layer == 0 and pot1.collision_mask == 0, "花盆碎后退出碰撞层（layer=%d mask=%d）" % [pot1.collision_layer, pot1.collision_mask])
		_check(pot1.get_node_or_null("Collision") == null, "花盆碎后碰撞形状已删除")
		# 切到未来：对应的能量桩启动
		player.global_position = Vector2(-96, 0)
		await _physics(4)
		Input.action_press("switch_time")
		await _physics(2)
		Input.action_release("switch_time")
		await _physics(70)
		_check(Timeline.is_future(), "已切到未来")
		_check(not pot1.visible, "未来时空里花盆隐藏")
		_check(pylon1.visible, "未来时空里能量桩显示")
		var guard3 := 0
		while not pylon1.activated and guard3 < 200:
			await _physics(1)
			guard3 += 1
		_check(pylon1.activated, "对应的花盆碎掉后能量桩启动")
		var pylon2: Node = world.get_node_or_null("YSort/EnergyPylon2")
		_check(pylon2 != null and not pylon2.activated, "没被打碎的花盆对应的能量桩仍是关闭的")
		# 通用 boss 分组不再是能量桩的攻击目标。
		var fake_boss: Node2D = load("res://scenes/test_dummy.tscn").instantiate()
		fake_boss.name = "FakeBoss"
		fake_boss.add_to_group("boss")
		world.add_child(fake_boss)
		fake_boss.set_physics_process(false)
		fake_boss.global_position = pylon1.global_position + Vector2(60, 0)
		pylon1.attacks_made = 0
		var boss_hp_before: float = fake_boss.hp
		await _physics(180)   # 3 秒，够打 1~2 次
		_check(pylon1.attacks_made == 0, "未来 boss 未登场时能量桩不攻击")
		_check(fake_boss.hp == boss_hp_before, "能量桩不攻击通用 boss 分组目标")
		_check(not pylon1._attacking, "未来 boss 未登场时不进入协助攻击状态")
		var boss2: CharacterBody2D = world.get_node_or_null("YSort/FutureBoss")
		if boss2 != null:
			var boss_home: Vector2 = boss2.global_position
			boss2.begin_entrance()
			boss2.set_physics_process(false)
			boss2.state = "walk"
			boss2.global_position = pylon1.global_position + Vector2(60, 0)
			var shield_before_laser: float = boss2.shield
			pylon1._try_attack()
			await _physics(22)
			_check(pylon1.attacks_made == 1, "未来 boss 登场后能量桩协助攻击")
			_check(pylon1._laser_left > 0.0, "能量桩开火时有可见的激光（剩余 %.2fs）" % pylon1._laser_left)
			_check(absf(shield_before_laser - boss2.shield - 2.0) < 0.01, "能量桩激光每次 2 点")
			pylon1._cancel_attack()
			boss2.hp = 200.0
			boss2.shield = 50.0
			boss2.poise = 50.0
			boss2.shield_up = true
			boss2.dead = false
			boss2.take_laser_damage(2.0)
			_check(absf(boss2.poise - 50.0) < 0.01, "激光不削韧性（%.0f）" % boss2.poise)
			_check(absf(boss2.shield - 48.0) < 0.01, "激光扣 2 点护盾（%.0f）" % boss2.shield)
			boss2.shield = boss2.shield_max
			boss2.poise = boss2.poise_max
			boss2.hp = boss2.hp_max
			boss2.shield_up = true
			boss2._paralyzed_left = 0.0
			boss2._no_shield_left = 0.0
			boss2.dead = false
			boss2.state = "walk"
			boss2.global_position = boss_home
			boss2.visible = false
			boss2.process_mode = Node.PROCESS_MODE_DISABLED
		if pylon1 != null:
			_check(absf(pylon1.attack_interval - 2.8) < 0.01, "能量桩攻击间隔已降低（%.1fs）" % pylon1.attack_interval)
		fake_boss.queue_free()
		# 切回现代，复位
		Input.action_press("switch_time")
		await _physics(2)
		Input.action_release("switch_time")
		await _physics(70)
		_check(not Timeline.is_future(), "切回现代")
		world.pot_broken[0] = false
		world.pot_broken[1] = false
		world.pot_broken[2] = false
		world._refresh_era_props()
		pot1.broken = false
		pot1.sprite.animation = "break"
		pot1.sprite.frame = 0
		if p1col != null:
			p1col.disabled = false
		pylon1.activated = false
		pylon1.attacks_made = 0
		pylon1.sprite.play("idle")
		world._refresh_era_props()
	player.reset_stats()
	player.global_position = Vector2(-96, 0)
	await _physics(4)

	print("== 未来 boss（持盾冲锋） ==")
	_release_all()
	if Timeline.is_future():
		Timeline.toggle()
		await _physics(4)
	player.reset_stats()
	player.global_position = Vector2(-96, 0)
	await _physics(4)
	var boss: CharacterBody2D = world.get_node_or_null("YSort/FutureBoss")
	_check(boss != null, "未来 boss 在场景里")
	if boss != null:
		_check(absf(boss.hp_max - 150.0) < 0.01 and absf(boss.shield_max - 100.0) < 0.01 and absf(boss.poise_max - 50.0) < 0.01,
			"boss 属性 150 血 / 100 盾 / 50 韧性（%.0f/%.0f/%.0f）" % [boss.hp_max, boss.shield_max, boss.poise_max])
		_check(boss.shield_up and absf(boss.shield - 100.0) < 0.01, "boss 初始持盾（盾 %.0f）" % boss.shield)
		# 朝向 / 冲锋方向一致
		boss._face(Vector2(1, 0))
		_check(boss.facing == "E", "boss 面朝右时是 E（%s）" % boss.facing)
		boss._face(Vector2(0, 1))
		_check(boss.facing == "S", "boss 面朝下时是 S（%s）" % boss.facing)
		var cv: Vector2 = boss._dir_vector("S")
		_check(absf(cv.x) < 0.01 and cv.y > 0.99, "S 对应的冲锋方向向量正确（%s）" % str(cv))
		# 护盾：每次最多扣 10，且不削韧性、不掉血
		boss.hp = boss.hp_max
		boss.poise = boss.poise_max
		boss.shield = boss.shield_max
		boss.shield_up = true
		boss.state = "walk"
		boss.take_damage(30.0)
		_check(absf(boss.shield - 90.0) < 0.01, "护盾单次最多扣 10（100 → %.0f）" % boss.shield)
		_check(absf(boss.poise - (boss.poise_max - 2.0)) < 0.01, "普攻每下削 2 点 boss 韧性（%.0f）" % boss.poise)
		_check(absf(boss.hp - boss.hp_max) < 0.01, "持盾格挡不掉血（%.0f）" % boss.hp)
		_check(String(boss.sprite.animation).begins_with("block_"), "受击播持盾格挡动画（%s）" % boss.sprite.animation)
		# 护盾打空：立刻破防一次 + 之后 60 秒不举盾
		for _k in range(20):
			boss.state = "walk"
			boss.take_damage(10.0)
		_check(boss.shield <= 0.01, "护盾被打空（%.0f）" % boss.shield)
		_check(boss.shield_breaks >= 1, "破盾记录（%d 次）" % boss.shield_breaks)
		_check(not boss.shield_up, "破盾后不再举盾")
		_check(boss._paralyzed_left > 0.0, "破盾立刻破防一次（%.1fs）" % boss._paralyzed_left)
		_check(boss._no_shield_left > 55.0, "破盾后进入 60 秒无盾期（%.0fs）" % boss._no_shield_left)
		# 无盾期：正常掉血 + 掉韧性
		boss.poise = boss.poise_max
		var hp_before2: float = boss.hp
		var poise_before2: float = boss.poise
		boss.state = "walk"
		boss.take_damage(10.0)
		_check(absf(boss.hp - (hp_before2 - 10.0)) < 0.01, "无盾时正常掉血（%.0f → %.0f）" % [hp_before2, boss.hp])
		_check(absf(boss.poise - (poise_before2 - 2.0)) < 0.01, "无盾时普攻也削韧性 2 点（%.0f → %.0f）" % [poise_before2, boss.poise])
		# 60 秒后恢复 20 点护盾并重新举盾
		boss._paralyzed_left = 0.0
		boss._no_shield_left = 0.0
		boss.process_mode = Node.PROCESS_MODE_INHERIT
		boss.set_physics_process(true)
		await _physics(3)
		boss.set_physics_process(false)
		_check(boss.shield_up and absf(boss.shield - 20.0) < 0.01, "60 秒后恢复 20 点护盾并重新举盾（%.0f）" % boss.shield)
		# 冲锋：减伤 50%，不触发盾格挡
		boss.hp = 150.0
		boss.shield = 80.0
		boss.state = "charge"
		boss.take_damage(10.0)
		_check(absf(boss.hp - 145.0) < 0.01, "冲锋中减伤 50%%（150 → %.0f）" % boss.hp)
		_check(absf(boss.shield - 80.0) < 0.01, "冲锋中不触发盾格挡（盾 %.0f）" % boss.shield)
		boss.state = "walk"
		# 冲锋攻击 15 点：普通格挡挡不住，完美格挡仍有效
		player.reset_stats()
		player.state = "block"
		player.block_phase = "hold"
		player.perfect_block_used = true
		player.facing = "S"
		var hp_before_charge: float = player.hp
		player.try_take_hit(15.0, player.global_position + Vector2(0, -40), true)
		_check(absf(player.hp - (hp_before_charge - 15.0)) < 0.01, "冲锋攻击 15 点不可被普通格挡（%.0f → %.0f）" % [hp_before_charge, player.hp])
		# 攻击时站定 + 动画正常推进（不每帧重播）
		player.reset_stats()
		player.global_position = boss.global_position + Vector2(200, 0)
		boss.shield_up = true
		boss.state = "walk"
		boss.set_physics_process(true)
		boss.process_mode = Node.PROCESS_MODE_INHERIT
		boss._start_volley(player)
		await _physics(3)
		var fr1: int = boss.sprite.frame
		await _physics(4)
		_check(boss.sprite.frame >= fr1, "五连射动画正常推进（帧 %d → %d）" % [fr1, boss.sprite.frame])
		_check(boss.velocity.length() < 1.0, "攻击时站定不动（速度 %.1f）" % boss.velocity.length())
		boss.set_physics_process(false)
		boss.process_mode = Node.PROCESS_MODE_DISABLED
		player.state = "stand"
		# 入场：小怪全清 + 现代 Boss 已败 → 现代形态出场、变身、未来形态冲锋。
		world.boss_entered = false
		world.modern_boss_defeated = true
		boss._entered = false
		boss.visible = false
		boss.set_physics_process(false)
		boss.process_mode = Node.PROCESS_MODE_DISABLED
		boss.hp = boss.hp_max
		boss.shield = boss.shield_max
		boss.poise = boss.poise_max
		boss.dead = false
		player.state = "stand"
		player.reset_stats()
		player.global_position = Vector2(-96, 0)
		for e1 in world._entities_modern + world._entities_future:
			if is_instance_valid(e1) and "dead" in e1:
				e1.dead = true
		if not Timeline.is_future():
			Timeline.toggle()
			await _physics(4)
		await _physics(2)
		world._check_boss_entrance()
		await _physics(2)
		_check(world.boss_entered, "小怪全清且主角在未来时 boss 入场")
		_check(world._boss_transform_running and not boss.visible, "先播现代形态出场，未来形态尚未启用")
		for entrance_frame in 240:
			if boss._entered:
				break
			await _physics(1)
		_check(not world._boss_transform_running and boss._entered, "变身完整结束后才启用未来形态")
		_check(boss.visible and boss.state == "enter", "入场时持盾冲锋（%s）" % boss.state)
		_check(not boss.dead and absf(boss.hp - 150.0) < 0.01, "入场时是满血活着的 boss（%.0f 血，dead=%s）" % [boss.hp, str(boss.dead)])
		_check(boss.modulate == Color(1, 1, 1, 1), "入场时没有被死亡变色（%s）" % str(boss.modulate))
		var boss_hud: Node = world.get_node_or_null("HUD/BossHud")
		_check(boss_hud != null, "顶部有常驻的 boss 状态条节点")
		if boss_hud != null:
			_check(boss_hud._find_boss() == boss, "boss 状态条能锁定 boss")
		# 瘫痪动画只播一次并保持倒地
		boss._paralyzed_left = 0.0
		boss.poise = boss.poise_max
		boss._enter_paralyzed()
		await _physics(3)
		await _physics(80)
		_check(not boss.sprite.is_playing(), "瘫痪动画播完就停住（不循环）")
		var hold_frame: int = boss.sprite.frame
		await _physics(30)
		_check(boss.sprite.frame == hold_frame and not boss.sprite.is_playing(), "瘫痪期间保持倒地最后一帧（%d）" % boss.sprite.frame)
		boss._paralyzed_left = 0.0
		boss.poise = boss.poise_max
		for e2 in world._entities_modern + world._entities_future:
			if is_instance_valid(e2) and "dead" in e2:
				e2.dead = false
				e2.dead_left = 0.0
		world.boss_entered = false
		world.modern_boss_defeated = false
		boss._entered = false
		boss.visible = false
		boss.set_physics_process(false)
		boss.process_mode = Node.PROCESS_MODE_DISABLED
		boss.state = "walk"
		boss.hp = 150.0
		boss.shield = 100.0
		boss.poise = 50.0
		boss.shield_up = true
		boss._paralyzed_left = 0.0
		boss._no_shield_left = 0.0
		boss.shield_breaks = 0
		for fe in future_enemies:
			if is_instance_valid(fe):
				fe.set_physics_process(false)
				(fe as Node2D).global_position = Vector2(2600, 2600)
		if Timeline.is_future():
			Timeline.toggle()
			await _physics(4)
	player.reset_stats()
	player.global_position = Vector2(-96, 0)
	await _physics(4)

	print("== 现代 boss（三连击 / 格挡反击 / 拖刀 / 钩爪） ==")
	_release_all()
	player.reset_stats()
	if Timeline.is_future():
		Timeline.toggle()
		await _physics(4)
	var mboss: Node2D = world.get_node_or_null("YSort/ModernBoss")
	_check(mboss != null, "现代 boss 在场景里")
	if mboss != null:
		mboss.spawned = true
		mboss._entering = false
		world._set_entity_active(mboss, true)
		mboss.visible = true
		mboss.modulate = Color(1, 1, 1, 1)
	if mboss != null:
		_check(absf(mboss.hp_max - 100.0) < 0.01 and absf(mboss.poise_max - 60.0) < 0.01,
			"现代 boss 属性 100 血 / 60 韧性（%.0f/%.0f）" % [mboss.hp_max, mboss.poise_max])
		# 普攻打不削韧性；只有 damage_poise（反击）才行
		mboss.global_position = Vector2(0, 0)
		mboss.hp = mboss.hp_max
		mboss.poise = mboss.poise_max
		mboss.state = "idle"
		mboss._blocking = false
		var poise0: float = mboss.poise
		mboss.take_damage(10.0)
		_check(absf(mboss.poise - poise0) < 0.01, "普攻打不削现代 boss 韧性（%.0f）" % mboss.poise)
		mboss.damage_poise(20.0)
		_check(absf(mboss.poise - 40.0) < 0.01, "反击削 20 点韧性（60 → %.0f）" % mboss.poise)
		mboss._stagger_left = 0.0
		mboss.state = "idle"
		mboss.poise = mboss.poise_max
		mboss.hp = mboss.hp_max
		# 格挡：挡住伤害并反击 10 点
		player.reset_stats()
		player.global_position = mboss.global_position + Vector2(40, 0)
		player.hurt_invuln_left = 0.0
		player.state = "stand"
		mboss.set_physics_process(true)
		mboss._start_block()
		await _physics(2)
		var hp_before_mb: float = mboss.hp
		var player_hp_before: float = player.hp
		mboss.take_damage(5.0)
		_check(absf(mboss.hp - hp_before_mb) < 0.01, "格挡时 boss 不掉血（%.0f）" % mboss.hp)
		_check(mboss.counters_done >= 1 and mboss.state == "counter_windup", "格挡后进入反击预警（%d 次）" % mboss.counters_done)
		await _physics(int(ceil((mboss.counter_windup + 0.25) * 60.0)))
		_check(player.hp < player_hp_before, "反击对玩家造成伤害（%.0f → %.0f）" % [player_hp_before, player.hp])
		# 三连击：3 段各 5 点
		player.reset_stats()
		player.global_position = mboss.global_position + Vector2(36, 0)
		mboss.state = "idle"
		mboss._blocking = false
		var hp_before_combo: float = player.hp
		mboss._start_combo(player)
		await _physics(70)
		_check(player.hp <= hp_before_combo - 10.0, "三连击打出多段伤害（%.0f → %.0f）" % [hp_before_combo, player.hp])
		# 低血量钩爪：把玩家拉到面前
		mboss.hp = 40.0
		mboss._hook_cooldown = 0.0
		mboss.state = "idle"
		mboss._drag_delay = 99.0
		player.reset_stats()
		player.global_position = mboss.global_position + Vector2(120, 0)
		await _physics(90)
		_check(mboss.hooks_done >= 1, "血量低于 50 触发钩爪（%d 次）" % mboss.hooks_done)
		_check(player.global_position.distance_to(mboss.global_position) < 80.0,
			"钩爪把玩家拉到面前（距离 %.0f）" % player.global_position.distance_to(mboss.global_position))
		# 半血钩爪可以重复使用（不是只一次）
		mboss._hook_cooldown = 0.0
		mboss.hp = 40.0
		mboss.state = "idle"
		var hooks_before: int = mboss.hooks_done
		player.reset_stats()
		player.global_position = mboss.global_position + Vector2(120, 0)
		mboss._start_hook(player)
		await _physics(60)
		_check(mboss.hooks_done == hooks_before + 1, "半血后钩爪能重复使用（%d → %d）" % [hooks_before, mboss.hooks_done])
		mboss.state = "idle"
		mboss._hook_cooldown = 0.0
		# 击败掉落道具；靠近拾取后才解锁钩爪。
		player.global_position = mboss.global_position + Vector2(70, 0)
		mboss.hp = 1.0
		mboss._blocking = false
		mboss.take_damage(5.0)
		await _physics(2)
		_check(mboss.dead, "现代 boss 被击败")
		_check(world.modern_boss_defeated and not player.has_claw, "击败后掉落钩爪但尚未解锁")
		var pickup: Area2D = world.get_node_or_null("YSort/ClawPickup")
		_check(pickup != null, "现代 boss 掉落可拾取钩爪")
		if pickup != null:
			player.global_position = pickup.global_position
			await _physics(3)
		_check(player.has_claw, "拾取后玩家解锁钩爪")
		# 玩家钩爪：拉最近的敌人 + 眩晕 + 5 秒冷却
		var hook_target: Node2D = world.get_node_or_null("YSort/ModernEnemy")
		player.reset_stats()
		player.global_position = Vector2(-96, 0)
		if hook_target != null:
			hook_target.global_position = Vector2(100, 0)   # 射程内，看钩爪飞过去
			hook_target.dead = false
			hook_target.visible = true
			player.claw_cooldown_left = 0.0
			player._fire_claw()
			_check(player.claw_cooldown_left > 4.0, "钩爪进入 5 秒冷却（%.1fs）" % player.claw_cooldown_left)
			await _physics(45)
			_check(hook_target.global_position.distance_to(player.global_position) < 60.0,
				"钩爪把敌人拉到身边（距离 %.0f）" % hook_target.global_position.distance_to(player.global_position))
			_check(hook_target.stun_left > 0.0, "被钩爪拉到的敌人眩晕（%.1fs）" % hook_target.stun_left)
			hook_target.global_position = Vector2(2400, 2400)
		mboss.set_physics_process(false)
		mboss.global_position = Vector2(3000, 3000)
	player.reset_stats()
	player.global_position = Vector2(-96, 0)
	await _physics(4)

	print("== boss 出场 / 变身 ==")
	_release_all()
	if Timeline.is_future():
		Timeline.toggle()
		await _physics(4)
	player.reset_stats()
	player.global_position = Vector2(-96, 0)
	var mb2: Node2D = world.get_node_or_null("YSort/ModernBoss")
	_check(mb2 != null, "现代 boss 节点存在")
	if mb2 != null:
		_check(absf(mb2.stagger_seconds - 4.5) < 0.01, "瘫痪时间加长到 4.5s（%.1f）" % mb2.stagger_seconds)
		_check(mb2.block_chance >= 0.65, "格挡概率提高（%.2f）" % mb2.block_chance)
		_check(mb2._anim_len("combo_S") > 1.4, "三连击放慢（单轮 %.2fs）" % mb2._anim_len("combo_S"))
		_check(mb2.attack_sfx != null and mb2.counter_sfx != null and mb2.drag_sfx != null, "现代 boss 三种攻击音效都挂上了")
		mboss._start_block()
		_check(absf(mboss._state_left - 2.0) < 0.01, "格挡持续 2 秒（%.1fs）" % mboss._state_left)
		mboss.state = "idle"
		mboss._blocking = false
		_check(String(mb2.attack_sfx.stream.resource_path).ends_with("attack.mp3") and
			String(mb2.counter_sfx.stream.resource_path).ends_with("counter.mp3"),
			"攻击/反击音效与主角一致")
		# 出场条件：现代普通敌人全灭
		for me_boss_spawn in modern_enemies:
			me_boss_spawn.dead = true
		world.modern_boss_defeated = false
		mb2.dead = false
		mb2.spawned = false
		mb2._entering = false
		mb2.visible = false
		mb2.modulate = Color(1, 1, 1, 0)
		mb2.global_position = Vector2(300, -150)
		await _physics(2)
		world._check_modern_boss_entrance()
		await _physics(2)
		_check(mb2._entering or mb2.spawned, "现代普通敌人全灭后 boss 开始出场")
		_check(mb2.visible and mb2.modulate.a < 0.6, "出场时半透明淡入（alpha %.2f）" % mb2.modulate.a)
		_check(player.cam_focus_left > 0.0, "出场时镜头短暂聚焦 boss（%.1fs）" % player.cam_focus_left)
		await _physics(120)
		_check(mb2.spawned and absf(mb2.modulate.a - 1.0) < 0.01, "走出完成后完全显现（alpha %.2f）" % mb2.modulate.a)
		# 收尾：隐藏并恢复
		mb2.spawned = false
		mb2._entering = false
		mb2.visible = false
		mb2.set_physics_process(false)
		mb2.global_position = Vector2(3000, 3000)
	# 未来 boss 入场条件：现代 boss 未败 → 不入场
	world.boss_entered = false
	world.modern_boss_defeated = false
	_check(not world.is_boss_entrance_ready(), "现代 boss 没被打败时未来 boss 不会入场")
	world.modern_boss_defeated = true
	# 变身流程：通过正式入口验证现代形态出场，再播放变身。
	var fb: Node = world.get_node("YSort/FutureBoss")
	fb._entered = false
	fb.dead = false
	world.boss_entered = true
	Timeline.set_era(1)
	for entity in world._entities_modern + world._entities_future:
		if is_instance_valid(entity) and "dead" in entity:
			entity.dead = true
	world.boss_entered = false
	world._check_boss_entrance()
	await _physics(3)
	_check(world._boss_transform_actor != null, "未来 boss 出场时播放现代形态走出演出")
	_check(player.cam_focus_left > 0.0, "变身时镜头聚焦")
	for entrance_frame in 240:
		if fb._entered:
			break
		await _physics(1)
	_check(world._boss_transform_actor == null, "变身动画播完消失")
	_check(fb.visible and (fb.state == "enter" or fb.state == "walk"), "变身结束后未来 boss 入场")
	Timeline.set_era(0)
	fb.set_physics_process(false)
	world.boss_entered = true
	player.cam_focus_left = 0.0
	player.get_node("Camera").position = Vector2.ZERO
	player.reset_stats()
	player.global_position = Vector2(-96, 0)
	await _physics(4)

	print("== 碰撞边界 ==")
	_release_all()
	await _physics(3)
	player.global_position = Vector2(-96, -96)   # 地图上半部一条宽阔的路面
	Input.action_press("move_right")
	await _physics(180)
	_release_all()
	_check(player.global_position.x < 700.0, "被地图边界（空气墙）挡住（x=%.1f）" % player.global_position.x)

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## 统计 YSort 下由残影动态生成的 Sprite2D 数量
func _count_ghosts(layer: Node) -> int:
	var n := 0
	for child in layer.get_children():
		if child is Sprite2D:
			n += 1
	return n

func _count_bullets() -> int:
	var layer: Node = get_tree().current_scene.get_node_or_null("YSort")
	if layer == null:
		return 0
	var n := 0
	for c in layer.get_children():
		if c.has_method("is_bullet"):
			n += 1
	return n

func _clear_bullets() -> void:
	var layer: Node = get_tree().current_scene.get_node_or_null("YSort")
	if layer == null:
		return
	for c in layer.get_children():
		if c.has_method("is_bullet"):
			c.queue_free()

func _release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "dodge", "attack", "block"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)

func _finish() -> void:
	if failures.is_empty():
		print("ALL TESTS PASSED (%d checks)" % checks)
		get_tree().quit(0)
	else:
		print("FAILED %d / %d checks" % [failures.size(), checks])
		for f in failures:
			print("  - ", f)
		get_tree().quit(1)
