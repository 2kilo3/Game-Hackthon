extends CharacterBody2D
signal defeated
## 现代的近战敌人（剑士）：平时来回走，发现玩家后奔跑接近，进入范围后快速攻击。
##
## 数值：生命 40 / 韧性 20。
## 体力 40（**不显示**，只参与逻辑）：
##   - 每次攻击消耗 5 点；
##   - 奔跑每秒消耗 1 点；
##   - 行走时每秒回复 5 点；
##   - 体力不足以支付对应操作时不能攻击/奔跑；
##   - 体力掉到 20 以下会被"力竭"锁住，必须先走回来，攒到 ≥20 才恢复攻击和奔跑。
##
## 韧性被打空 → 瘫痪 5 秒；生命归零 → 倒下、隐藏血条、尸体 20 秒后消失。

@export_group("生命")
@export var hp_max := 40.0
@export var poise_max := 20.0
## 韧性被打破后的瘫痪时长（秒）
@export var poise_break_seconds := 5.0
## 倒下后尸体保留多久（秒）
@export var corpse_seconds := 20.0

@export_group("体力（不显示）")
@export var stamina_max := 40.0
## 每次攻击消耗
@export var attack_cost := 5.0
## 奔跑每秒消耗
@export var run_drain_per_sec := 1.0
## 行走每秒回复
@export var walk_regen_per_sec := 5.0
## 体力回到这个值以上才恢复攻击/奔跑
@export var resume_threshold := 20.0

@export_group("移动")
@export var walk_speed := 52.0
@export var run_speed := 122.0
@export var accel := 800.0
@export var decel := 1000.0
## 玩家进入这个半径开始追（三个敌人分站三个路口，缩小到 170 避免一进场就全追过来）
@export var detect_radius := 170.0
## 进入这个距离就攻击
@export var attack_range := 46.0

@export_group("攻击")
@export var attack_damage := 6.0
## 两次攻击之间的间隔（攻速较快）
@export var attack_cooldown := 0.55
## 动画播到多少比例时判定命中（前 3 帧是放慢的举刀，命中在其后 ≈0.63s）
@export var hit_ratio := 0.62

@export_group("巡逻")
@export var patrol_radius := 110.0
## 到点后停多久再选下一个点
@export var patrol_pause := 1.2

const DIRS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var bars: Node2D = $Bars

var hp := 40.0
var poise := 20.0
var stamina := 40.0
var paralyzed_left := 0.0
var dead := false
var dead_left := 0.0
## 力竭锁定：体力 < 20 时锁住攻击/奔跑，回到 20 以上解锁
var exhausted := false

## 调试/测试用
var facing := "S"
var attacks_made := 0
var hits_dealt := 0
var state := "walk"

var _home := Vector2.ZERO
var _world: Node = null
var _patrol_target := Vector2.ZERO
var _patrol_wait := 0.0
var _attack_timer := 0.0        # 距离下次可攻击
var _attacking := false
var _attack_hit_done := false
var _attack_elapsed := 0.0
var _attack_len := 0.45
## 刷新（初次进入玩家视野）相关
var _spawn_done := false
var _spawning := false
var _spawn_phase_left := 0.0
## 破防动画阶段："" / enter / hold / recover
var _break_phase := ""
var _break_phase_left := 0.0
## 死亡：先播破防"进入"，再停在被击破的循环姿势上（当尸体）
var _dead_anim_left := 0.0
## 眩晕剩余时间（钩爪）
var stun_left := 0.0

func _ready() -> void:
	hp = hp_max
	poise = poise_max
	stamina = stamina_max
	_home = global_position
	_pick_patrol_target()
	if bars != null:
		bars.visible = true
	facing = "S"
	_idle_pose()

func _physics_process(delta: float) -> void:
	if stun_left > 0.0:
		stun_left = maxf(0.0, stun_left - delta)
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		return

	if dead:
		velocity = Vector2.ZERO
		dead_left = maxf(0.0, dead_left - delta)
		# 死亡也用破防动画：先播"进入"，播完后停在"被击破"的姿势当尸体
		if _dead_anim_left > 0.0:
			_dead_anim_left -= delta
			if _dead_anim_left <= 0.0:
				sprite.play(_anim_name("break_hold", facing))
		if dead_left <= 0.0:
			queue_free()
		return

	# 刷新动画：第一次出现在玩家视野时播一次"生成"动作 + 音效（现代用音频的后 3 秒）
	if not _spawn_done:
		if _spawning:
			_spawn_phase_left -= delta
			velocity = Vector2.ZERO
			if _spawn_phase_left <= 0.0:
				_spawning = false
				_spawn_done = true
			_refresh_bars()
			return
		if _is_on_screen():
			_start_spawn()
			return
		velocity = Vector2.ZERO
		_idle_pose()
		return

	# 瘫痪：不动不攻击，播 进入 → 循环 → 恢复（恢复动画播完才算结束）
	if paralyzed_left > 0.0 or _break_phase != "":
		_update_break_anim(delta)
		velocity = velocity.move_toward(Vector2.ZERO, decel * delta)
		move_and_slide()
		_refresh_bars()
		return

	_attack_timer = maxf(0.0, _attack_timer - delta)

	# 兜底：万一被挤出可走区域，先走回出生点，避免站到地图外
	if not _is_on_floor_at(global_position):
		state = "walk"
		var back: Vector2 = _home - global_position
		if back.length() > 4.0:
			velocity = velocity.move_toward(back.normalized() * walk_speed, accel * delta)
		else:
			velocity = Vector2.ZERO
		move_and_slide()
		_face_and_animate(back)
		_refresh_bars()
		return

	# 正在攻击：站定播动画，命中判定一次
	if _attacking:
		_attack_elapsed += delta
		velocity = velocity.move_toward(Vector2.ZERO, decel * delta)
		move_and_slide()
		state = "attack"
		if not _attack_hit_done and _attack_elapsed >= _attack_len * hit_ratio:
			_attack_hit_done = true
			_do_attack_hit()
		if _attack_elapsed >= _attack_len:
			_attacking = false
			_attack_timer = attack_cooldown
		_refresh_bars()
		return

	var player := _find_player()
	var dist := INF
	if player != null:
		dist = global_position.distance_to(player.global_position)

	# 体力：跑步扣、走路回
	var is_running := state == "run"

	if player != null and dist <= detect_radius:
		var to_player: Vector2 = player.global_position - global_position
		var dir := to_player.normalized()
		var can_attack := _can_attack()
		if dist <= attack_range and can_attack:
			_start_attack(player)
			# 攻击这一帧直接返回：不再走移动/换动画的流程，保证攻击动作完整播完
			_refresh_bars()
			return
		elif dist > attack_range * 0.85:
			if _can_run():
				state = "run"
				velocity = velocity.move_toward(dir * run_speed, accel * delta)
			else:
				state = "walk"
				velocity = velocity.move_toward(dir * walk_speed, accel * delta)
		else:
			state = "walk"
			velocity = velocity.move_toward(Vector2.ZERO, decel * delta)
		move_and_slide()
		_update_stamina(delta, state == "run")
		_face_and_animate(velocity if velocity.length() > 4.0 else (player.global_position - global_position))
	else:
		_patrol(delta)

	_refresh_bars()

# ---------------- 体力 ----------------
func _update_stamina(delta: float, running: bool) -> void:
	if running:
		stamina = maxf(0.0, stamina - run_drain_per_sec * delta)
	else:
		stamina = minf(stamina_max, stamina + walk_regen_per_sec * delta)
	# 力竭：体力真的用完（连奔跑都付不起）才锁住；
	# 锁住后必须先走回来，攒到 resume_threshold（20）以上才恢复攻击和奔跑
	if stamina <= 0.01:
		exhausted = true
	elif exhausted and stamina >= resume_threshold:
		exhausted = false

func _can_attack() -> bool:
	return not exhausted and stamina >= attack_cost and _attack_timer <= 0.0

func _can_run() -> bool:
	return not exhausted and stamina > 1.0

# ---------------- 巡逻 ----------------
func _pick_patrol_target() -> void:
	# 只在"可走地面"上选巡逻点：从远到近试几圈，保证一定能找到一个能走的点
	for frac in [1.0, 0.7, 0.45, 0.25]:
		for _try in range(8):
			var ang := randf() * TAU
			var r: float = patrol_radius * frac
			var cand: Vector2 = _home + Vector2(cos(ang), sin(ang) * 0.6) * r
			if cand.distance_to(global_position) > 8.0 and _is_on_floor_at(cand):
				_patrol_target = cand
				return
	# 实在找不到（比如被挤到很小的地方）：朝 8 个方向里第一个能走的方向挪一点
	for k in range(8):
		var dir := Vector2(cos(TAU * float(k) / 8.0), sin(TAU * float(k) / 8.0) * 0.6)
		var p2: Vector2 = _home + dir * 28.0
		if _is_on_floor_at(p2):
			_patrol_target = p2
			return
	_patrol_target = global_position

## 这个坐标能不能站：既要"在栅栏围成的可玩区域内"，又要有地板
func _is_on_floor_at(p: Vector2) -> bool:
	var w: Node = _world_node()
	if w != null and w.has_method("is_inside_play_area"):
		if not bool(w.is_inside_play_area(p)):
			return false
	if w != null and w.has_method("is_walkable_point"):
		return bool(w.is_walkable_point(p))
	return true

func _world_node() -> Node:
	if _world != null and is_instance_valid(_world):
		return _world
	var p := get_parent()
	if p != null:
		_world = p.get_parent()
	return _world

func _patrol(delta: float) -> void:
	if _patrol_wait > 0.0:
		_patrol_wait = maxf(0.0, _patrol_wait - delta)
		state = "walk"
		velocity = velocity.move_toward(Vector2.ZERO, decel * delta)
		move_and_slide()
		_update_stamina(delta, false)
		_face_and_animate(Vector2.ZERO)
		return
	var to_target: Vector2 = _patrol_target - global_position
	if to_target.length() <= 10.0:
		_patrol_wait = patrol_pause
		_pick_patrol_target()
		state = "walk"
		velocity = velocity.move_toward(Vector2.ZERO, decel * delta)
		move_and_slide()
		_update_stamina(delta, false)
		_face_and_animate(Vector2.ZERO)
		return
	state = "walk"
	velocity = velocity.move_toward(to_target.normalized() * walk_speed * 0.8, accel * delta)
	move_and_slide()
	_update_stamina(delta, false)
	_face_and_animate(to_target)

# ---------------- 攻击 ----------------
func _start_attack(player: Node2D) -> void:
	_attacking = true
	_attack_hit_done = false
	_attack_elapsed = 0.0
	state = "attack"
	attacks_made += 1
	velocity = Vector2.ZERO
	facing = _dir_name(player.global_position - global_position)
	_play_anim("attack", facing, true)
	_attack_len = _anim_length("attack", facing)
	# 攻击消耗体力
	stamina = maxf(0.0, stamina - attack_cost)
	if stamina <= 0.01:
		exhausted = true

func _do_attack_hit() -> void:
	var player := _find_player()
	if player == null:
		return
	if global_position.distance_to(player.global_position) <= attack_range + 10.0:
		if player.has_method("try_take_hit"):
			player.try_take_hit(attack_damage, global_position)
			hits_dealt += 1

# ---------------- 朝向 / 动画 ----------------
func _face_and_animate(v: Vector2) -> void:
	if v.length() < 0.001:
		_idle_pose()
		return
	facing = _dir_name(v)
	_play_anim(state if state == "run" else "walk", facing)

## 站定：停在"双腿并拢"的中间帧，避免定格在迈步姿势像在走路
func _idle_pose() -> void:
	sprite.pause()
	sprite.animation = "walk_" + facing
	var cnt := 8
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(sprite.animation):
		cnt = sprite.sprite_frames.get_frame_count(sprite.animation)
	sprite.frame = mini(2, cnt - 1)

func _dir_name(v: Vector2) -> String:
	if v.length() < 0.001:
		return facing
	var deg := rad_to_deg(v.angle())
	var idx := int(round(deg / 45.0)) % 8
	if idx < 0:
		idx += 8
	return DIRS[idx]

func _anim_name(action: String, dir: String) -> String:
	return "%s_%s" % [action, dir]

func _play_anim(action: String, dir: String, restart := false, hold := false) -> void:
	var anim := _anim_name(action, dir)
	if sprite.animation != anim or restart:
		sprite.play(anim)
		sprite.frame = 0
	elif not sprite.is_playing() and not hold:
		sprite.play(anim)

func _anim_length(action: String, dir: String) -> float:
	var frames := sprite.sprite_frames
	if frames == null:
		return 0.45
	var anim := _anim_name(action, dir)
	if not frames.has_animation(anim):
		return 0.45
	var fps := frames.get_animation_speed(anim)
	if fps <= 0.0:
		fps = 10.0
	# 每帧 duration 是"帧时长倍率"，攻击前 3 帧故意设成 2.4 来放慢起手
	var total := 0.0
	for i in range(frames.get_frame_count(anim)):
		total += frames.get_frame_duration(anim, i)
	return total / fps

# ---------------- 受击 ----------------
func take_damage(amount: float) -> void:
	if dead:
		return
	hp = maxf(0.0, hp - maxf(0.0, amount))
	if hp <= 0.0:
		_die()
	_refresh_bars()

func damage_poise(amount: float) -> void:
	if dead:
		return
	poise = clampf(poise - maxf(0.0, amount), 0.0, poise_max)
	if poise <= 0.0 and paralyzed_left <= 0.0:
		paralyzed_left = poise_break_seconds
		_break_phase = ""
		_attacking = false
	_refresh_bars()

func is_paralyzed() -> bool:
	return paralyzed_left > 0.0

func is_broken() -> bool:
	return dead

## 被玩家钩爪拉到身边后的眩晕：短时间内不动、不攻击
func stun(seconds: float) -> void:
	if dead:
		return
	stun_left = maxf(stun_left, seconds)
	velocity = Vector2.ZERO

func _die() -> void:
	if dead:
		return
	dead = true
	dead_left = corpse_seconds
	_attacking = false
	velocity = Vector2.ZERO
	_break_phase = ""
	# 死亡用破防动画：进入 → 停在循环姿势（尸体）
	_dead_anim_left = _anim_seconds(_anim_name("break_enter", facing))
	sprite.play(_anim_name("break_enter", facing))
	modulate = Color(0.55, 0.55, 0.6, 0.85)
	if bars != null:
		bars.visible = false
	var col: CollisionShape2D = get_node_or_null("Collision")
	if col != null:
		col.disabled = true
	defeated.emit()

func _refresh_bars() -> void:
	if bars != null:
		bars.queue_redraw()

func _find_player() -> Node2D:
	var n := get_parent().get_node_or_null("Player")
	if n is Node2D:
		return n
	return null

## 是否已经出现在玩家屏幕上
func _is_on_screen() -> bool:
	var vp := get_viewport()
	if vp == null:
		return true
	var rect: Rect2 = vp.get_visible_rect().grow(8.0)
	return rect.has_point(get_global_transform_with_canvas().origin)

func _start_spawn() -> void:
	var player := _find_player()
	if player != null:
		facing = _dir_name(player.global_position - global_position)
	_spawning = true
	_spawn_phase_left = _anim_seconds(_anim_name("spawn", facing))
	sprite.play(_anim_name("spawn", facing))

## 破防动画：进入 → 循环 → 恢复，恢复完韧性回满
func _update_break_anim(delta: float) -> void:
	if _break_phase == "":
		_break_phase = "enter"
		_break_phase_left = _anim_seconds(_anim_name("break_enter", facing))
		sprite.play(_anim_name("break_enter", facing))
		paralyzed_left = maxf(0.0, paralyzed_left - delta)
		return
	if _break_phase == "enter":
		_break_phase_left -= delta
		if _break_phase_left <= 0.0:
			_break_phase = "hold"
			sprite.play(_anim_name("break_hold", facing))
		paralyzed_left = maxf(0.0, paralyzed_left - delta)
		return
	if _break_phase == "hold":
		paralyzed_left = maxf(0.0, paralyzed_left - delta)
		if paralyzed_left <= 0.0:
			_break_phase = "recover"
			_break_phase_left = _anim_seconds(_anim_name("break_recover", facing))
			sprite.play(_anim_name("break_recover", facing))
		return
	_break_phase_left -= delta
	if _break_phase_left <= 0.0:
		_break_phase = ""
		poise = poise_max
		_attack_timer = 0.0

## 某动画的时长（秒）
func _anim_seconds(anim: String) -> float:
	var sf := sprite.sprite_frames
	if sf == null or not sf.has_animation(anim):
		return 0.4
	var fps := sf.get_animation_speed(anim)
	if fps <= 0.0:
		fps = 10.0
	var total := 0.0
	for i in range(sf.get_frame_count(anim)):
		total += sf.get_frame_duration(anim, i)
	return total / fps

