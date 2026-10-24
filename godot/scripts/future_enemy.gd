extends CharacterBody2D
signal defeated
## 未来时空的枪手：会追着玩家走，站定后一轮打 3 发子弹。
##
## 数值：生命 40 / 韧性 50 / 能量 20；每轮开火消耗 5 点能量。
## 能量不够一轮时停止开火，10 秒后能量回满，然后继续开火。
## 韧性被打空 → 瘫痪 5 秒（不动、不开火），结束后韧性回满。
## 生命归零 → 倒下（隐藏、不再行动）。

@export_group("生命")
@export var hp_max := 40.0
@export var poise_max := 50.0
## 韧性被打破后的瘫痪时长（秒）
@export var poise_break_seconds := 5.0
## 倒下后尸体保留多久（秒），到点删除
@export var corpse_seconds := 20.0

@export_group("能量")
@export var energy_max := 20.0
## 每开一次枪（一轮 3 发）消耗的能量
@export var shot_cost := 5.0
## 能量耗尽后多久回满（秒）
@export var energy_recover_seconds := 10.0

@export_group("移动")
@export var move_speed := 78.0
## 玩家进入这个半径才开始追/开枪（5 个敌人分散站位，缩小到 260 避免一起开火）
@export var detect_radius := 260.0
## 与玩家保持的距离（近了会后退）
@export var keep_distance := 150.0
@export var accel := 900.0
@export var decel := 1200.0

@export_group("射击")
## 两轮之间的间隔（秒）
@export var shoot_cooldown := 2.0
## 一轮几发
@export var volley_count := 3
## 一轮内两发之间的间隔（秒）= 一次开枪动画的时长（4 帧 @12fps ≈ 0.333s）
## 三发 ≈ 1 秒，也就是"开枪站立"的总时长
@export var volley_gap := 0.34
@export var bullet_damage := 2.0
@export var bullet_speed := 340.0
@export var bullet_max_distance := 420.0

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const DIRS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const DIR_NAMES := {
	"E": "right", "SE": "downright", "S": "down", "SW": "downleft",
	"W": "left", "NW": "upleft", "N": "up", "NE": "upright",
}

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var muzzle: AnimatedSprite2D = $Muzzle
@onready var bars: Node2D = $Bars
@onready var shoot_sfx: AudioStreamPlayer = $ShootSfx

var hp := 40.0
var poise := 50.0
var energy := 20.0
## 韧性破裂后的瘫痪剩余秒数
var paralyzed_left := 0.0
## 能量耗尽后的恢复剩余秒数
var recover_left := 0.0
var dead := false
## 倒下后尸体剩余时间（秒）
var dead_left := 0.0

## 调试/测试用计数
var bullets_fired := 0
var volleys_fired := 0
var facing := "S"

var _shoot_timer := 0.0      # 距离下一轮
var _shots_left := 0         # 本轮还剩几发
var _shot_timer := 0.0       # 距离下一发
var _shooting := false
## 刷新（初次进入玩家视野）相关
var _spawn_done := false
var _spawning := false
## 破防动画阶段："" / enter / hold / recover
var _break_phase := ""
var _break_phase_left := 0.0
var _spawn_phase_left := 0.0
## 死亡：先播破防"进入"，再停在被击破的循环姿势上（当尸体）
var _dead_anim_left := 0.0
## 眩晕剩余时间（钩爪）
var stun_left := 0.0

func _ready() -> void:
	hp = hp_max
	poise = poise_max
	energy = energy_max
	if muzzle != null:
		muzzle.visible = false
		muzzle.animation_finished.connect(func() -> void: muzzle.visible = false)
	_stand_still()

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
				sprite.play("break_hold_" + String(DIR_NAMES.get(facing, "down")))
		if dead_left <= 0.0:
			queue_free()
		return

	# 刷新动画：第一次出现在玩家视野时播一次"生成"动作 + 音效
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
		_stand_still()
		return

	# 瘫痪：不动不开火，播 进入 → 循环 → 恢复（恢复动画播完才算结束）
	if paralyzed_left > 0.0 or _break_phase != "":
		_update_break_anim(delta)
		velocity = velocity.move_toward(Vector2.ZERO, decel * delta)
		move_and_slide()
		_refresh_bars()
		return

	# 能量恢复：耗尽后 10 秒回满，然后继续开火
	if energy < shot_cost:
		recover_left = maxf(0.0, recover_left - delta)
		if recover_left <= 0.0:
			energy = energy_max
			_shoot_timer = 0.0
	else:
		recover_left = 0.0

	var player := _find_player()
	var dist := INF
	if player != null:
		dist = global_position.distance_to(player.global_position)

	_move(delta, player, dist)
	_update_shooting(delta, player, dist)
	_refresh_bars()

# ---------------- 移动 ----------------
func _move(delta: float, player: Node2D, dist: float) -> void:
	# 抬枪/射击期间原地不动
	if _shooting:
		velocity = Vector2.ZERO
		return
	var desired := Vector2.ZERO
	if player != null and dist <= detect_radius and not _shooting:
		var to_player: Vector2 = player.global_position - global_position
		if to_player.length() > 1.0:
			var dir := to_player.normalized()
			if dist > keep_distance + 12.0:
				desired = dir * move_speed
			elif dist < keep_distance - 12.0:
				desired = -dir * move_speed * 0.8
			else:
				# 保持距离时绕着玩家慢慢横移，看上去在活动
				desired = dir.orthogonal() * move_speed * 0.45
	velocity = velocity.move_toward(desired, (accel if desired != Vector2.ZERO else decel) * delta)
	move_and_slide()

	if velocity.length() > 8.0:
		var dname := _dir_name(velocity)
		_play_walk(dname, delta)
		facing = dname
	else:
		# 站定时：面向玩家（看不见玩家就保持原朝向），并停在"双腿并拢"的中间帧，
		# 不然定格在迈步姿势会让人以为它一直在走
		if player != null:
			facing = _dir_name(player.global_position - global_position)
		sprite.pause()
		sprite.animation = "walk_" + DIR_NAMES.get(facing, "down")
		sprite.frame = 2

func _play_walk(dir_name: String, _delta: float) -> void:
	var anim: String = "walk_" + String(DIR_NAMES.get(dir_name, "down"))
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)

# ---------------- 射击 ----------------
func _update_shooting(delta: float, player: Node2D, dist: float) -> void:
	if player == null:
		return
	# 连发：每发都单独播一次开枪动作（4 帧），三发 ≈ 1 秒
	if _shooting:
		_shot_timer -= delta
		if _shots_left > 0 and _shot_timer <= 0.0:
			_play_shoot_anim()
			_fire(player)
			_shots_left -= 1
			_shot_timer = volley_gap
		if _shots_left <= 0 and _shot_timer <= 0.0:
			_shooting = false
			_shoot_timer = shoot_cooldown
		return

	_shoot_timer = maxf(0.0, _shoot_timer - delta)
	if _shoot_timer > 0.0:
		return
	if dist > detect_radius:
		return
	if energy < shot_cost:
		return
	_start_volley(player)

func _start_volley(player: Node2D) -> void:
	energy = maxf(0.0, energy - shot_cost)
	volleys_fired += 1
	if energy < shot_cost:
		recover_left = energy_recover_seconds
	_shooting = true
	_shots_left = volley_count
	_shot_timer = 0.0
	facing = _dir_name(player.global_position - global_position)
	_play_shoot_anim()
	_fire(player)
	_shots_left -= 1
	_shot_timer = volley_gap

## 每发子弹一声枪响，离玩家越远越小
func _play_shoot_sfx() -> void:
	if shoot_sfx == null or shoot_sfx.stream == null:
		return
	var p := _find_player()
	var atten := 1.0
	if p != null:
		atten = clampf(1.0 - global_position.distance_to(p.global_position) / 700.0, 0.2, 1.0)
	shoot_sfx.volume_db = -14.0 + linear_to_db(atten)
	shoot_sfx.play()

## 播一次开枪动作（4 帧 @12fps）+ 枪口火光；三发各播一次
func _play_shoot_anim() -> void:
	var anim: String = "shoot_" + String(DIR_NAMES.get(facing, "down"))
	sprite.play(anim)
	sprite.frame = 0
	if muzzle != null:
		muzzle.play("muzzle_" + String(DIR_NAMES.get(facing, "down")))
		muzzle.frame = 0
		muzzle.visible = true

func _fire(player: Node2D) -> void:
	_play_shoot_sfx()
	if player == null or not (player is Node2D):
		return
	var bullet := BULLET_SCENE.instantiate()
	bullet.direction = (player.global_position - global_position).normalized()
	bullet.speed = bullet_speed
	bullet.damage = bullet_damage
	bullet.max_distance = bullet_max_distance
	bullet.source_pos = global_position
	var layer := get_parent()
	layer.add_child(bullet)
	bullet.global_position = global_position
	bullets_fired += 1

func _dir_name(v: Vector2) -> String:
	if v.length() < 0.001:
		return facing
	var deg := rad_to_deg(v.angle())
	var idx := int(round(deg / 45.0)) % 8
	if idx < 0:
		idx += 8
	return DIRS[idx]

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
		_shots_left = 0
		_shooting = false
	if bars != null:
		bars.queue_redraw()

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
	velocity = Vector2.ZERO
	_shooting = false
	_shots_left = 0
	_break_phase = ""
	# 死亡用破防动画：进入 → 停在循环姿势（尸体）
	var die_dir := String(DIR_NAMES.get(facing, "down"))
	_dead_anim_left = _anim_seconds("break_enter_" + die_dir)
	sprite.play("break_enter_" + die_dir)
	modulate = Color(0.55, 0.55, 0.6, 0.85)
	if muzzle != null:
		muzzle.visible = false
	if bars != null:
		bars.visible = false   # 死亡后不再显示血条
	var col: CollisionShape2D = get_node_or_null("Collision")
	if col != null:
		col.disabled = true
	_refresh_bars()
	defeated.emit()

func _refresh_bars() -> void:
	if bars != null:
		bars.queue_redraw()

func _find_player() -> Node2D:
	var n := get_parent().get_node_or_null("Player")
	if n is Node2D:
		return n
	return null

## 还没被玩家看到时：原地站好，不要播走路动画
func _stand_still() -> void:
	sprite.pause()
	sprite.animation = "walk_" + String(DIR_NAMES.get(facing, "down"))
	sprite.frame = 2

## 是否已经出现在玩家屏幕上（用于"初次进入视野"的刷新动画）
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
	_spawn_phase_left = _anim_seconds("spawn_" + String(DIR_NAMES.get(facing, "down")))
	sprite.play("spawn_" + String(DIR_NAMES.get(facing, "down")))
	if muzzle != null:
		muzzle.visible = false

## 破防动画：进入（6 帧）→ 循环（4 帧）→ 恢复（6 帧），恢复完韧性回满
func _update_break_anim(delta: float) -> void:
	var dir_name := String(DIR_NAMES.get(facing, "down"))
	if _break_phase == "":
		_break_phase = "enter"
		_break_phase_left = _anim_seconds("break_enter_" + dir_name)
		sprite.play("break_enter_" + dir_name)
		paralyzed_left = maxf(0.0, paralyzed_left - delta)
		return
	if _break_phase == "enter":
		_break_phase_left -= delta
		if _break_phase_left <= 0.0:
			_break_phase = "hold"
			sprite.play("break_hold_" + dir_name)
		paralyzed_left = maxf(0.0, paralyzed_left - delta)
		return
	if _break_phase == "hold":
		paralyzed_left = maxf(0.0, paralyzed_left - delta)
		if paralyzed_left <= 0.0:
			_break_phase = "recover"
			_break_phase_left = _anim_seconds("break_recover_" + dir_name)
			sprite.play("break_recover_" + dir_name)
		return
	# recover
	_break_phase_left -= delta
	if _break_phase_left <= 0.0:
		_break_phase = ""
		poise = poise_max
		_shoot_timer = 0.0

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

