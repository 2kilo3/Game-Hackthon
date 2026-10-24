extends CharacterBody2D
## 现代 boss：持刀剑客
##
## - 生命 100 / 韧性 60
## - 随机出招：三连击（每段 5 点伤害）或 格挡
## - 格挡期间被玩家普攻打到 → 预警蓄力后反击（10 点伤害）
## - 技能：加速拖刀冲刺，接拖刀斩（10 点伤害）
## - 生命 < 50 时触发一次钩爪攻击：把玩家拉到面前并接三连击
## - 韧性只由玩家的**反击**削减（`damage_poise`），打空后瘫痪
## - 被击败后发 `defeated` 信号（世界据此把钩爪技能给玩家）

signal defeated
signal appeared

const DIRS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

@export var hp_max := 100.0
@export var poise_max := 60.0
@export var walk_speed := 70.0
@export var drag_speed := 240.0
@export var combo_range := 62.0
@export var combo_damage := 5.0
@export var counter_damage := 10.0
@export var counter_windup := 0.65
@export var drag_damage := 10.0
@export var hook_hp_threshold := 50.0
@export var stagger_seconds := 4.5
@export var corpse_seconds := 20.0
@export var block_seconds := 2.0
@export var decision_interval := 1.4
## 格挡概率（提高）
@export var block_chance := 0.7
## 出场：缓缓走出 + 透明度从 100%（透明）到 0%（不透明）
@export var entrance_walk_seconds := 1.3
@export var detect_radius := 460.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var bars: Node2D = $Bars
@onready var attack_sfx: AudioStreamPlayer = $AttackSfx
@onready var counter_sfx: AudioStreamPlayer = $CounterSfx
@onready var drag_sfx: AudioStreamPlayer = $DragSfx

var hp := 100.0
var poise := 60.0
var dead := false
var dead_left := 0.0
var facing := "S"
## 状态：idle / walk / combo / block / counter_windup / counter / drag / drag_slash / hook / stagger / die
var state := "idle"

var _decision_left := 1.2
var _state_left := 0.0
var _combo_step := 0
var _combo_gap := 0.0
var _combo_hit_done := false
var _drag_phase := 0
var _blocking := false
## 钩爪冷却（半血解锁后可重复使用）
var _hook_cooldown := 0.0
var hook_cooldown_time := 6.0
var _stagger_left := 0.0
var _drag_delay := 6.0
var _hook_pull_done := false
var _attack_target: Node2D = null
## 眩晕（玩家钩爪）
var stun_left := 0.0
## 调试/测试
var combos_done := 0
var counters_done := 0
var drags_done := 0
var hooks_done := 0
var blocked_hits := 0
## 出场动画状态
var spawned := false
var _entering := false
var _entrance_left := 0.0

func _ready() -> void:
	add_to_group("modern_boss")
	hp = hp_max
	poise = poise_max
	spawned = false
	_entering = false
	visible = false
	modulate = Color(1, 1, 1, 0)
	_play("stand")
	if bars != null:
		bars.visible = true

## 由世界调用：现代普通敌人全灭后缓缓走出来
func begin_entrance() -> void:
	if spawned or _entering:
		return
	visible = true
	modulate = Color(1, 1, 1, 0)
	hp = hp_max
	poise = poise_max
	dead = false
	dead_left = 0.0
	_blocking = false
	state = "idle"
	_entering = true
	_entrance_left = entrance_walk_seconds
	set_physics_process(true)
	if bars != null:
		bars.visible = true

func _physics_process(delta: float) -> void:
	# 出场：缓缓走出 + 透明度从 100%（全透明）到 0%（不透明）
	if _entering:
		_entrance_left -= delta
		var prog: float = clampf(1.0 - _entrance_left / entrance_walk_seconds, 0.0, 1.0)
		modulate = Color(1, 1, 1, prog)
		var target := _find_player()
		if target != null:
			var dir: Vector2 = (target.global_position - global_position).normalized()
			velocity = dir * walk_speed * 0.8
			_face(dir)
			_play("walk")
		move_and_slide()
		if _entrance_left <= 0.0:
			_entering = false
			spawned = true
			modulate = Color(1, 1, 1, 1)
			appeared.emit()
		return

	if not spawned and not _entering:
		velocity = Vector2.ZERO
		return

	if dead:
		velocity = Vector2.ZERO
		dead_left = maxf(0.0, dead_left - delta)
		if dead_left <= 0.0:
			queue_free()
		return

	if stun_left > 0.0:
		stun_left = maxf(0.0, stun_left - delta)
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		_refresh_bars()
		return

	if _stagger_left > 0.0:
		_stagger_left = maxf(0.0, _stagger_left - delta)
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		_refresh_bars()
		return

	var player := _find_player()
	if player == null:
		return
	var to_player: Vector2 = player.global_position - global_position
	if state != "counter":
		_face(to_player)

	match state:
		"combo":
			_update_combo(delta, player)
			return
		"block":
			_update_block(delta)
			return
		"counter":
			_update_counter(delta)
			return
		"counter_windup":
			_update_counter_windup(delta)
			return
		"drag":
			_update_drag(delta, player)
			return
		"drag_slash":
			_update_drag_slash(delta, player)
			return
		"hook":
			_update_hook(delta, player)
			return

	# idle / walk
	_drag_delay -= delta
	if _decision_left <= 0.0 and to_player.length() <= combo_range + 10.0:
		_decision_left = decision_interval
		if randf() < block_chance:
			_start_block()
		else:
			_start_combo(player)
		return
	if _hook_cooldown > 0.0:
		_hook_cooldown = maxf(0.0, _hook_cooldown - delta)
	if hp <= hook_hp_threshold and _hook_cooldown <= 0.0 and to_player.length() < 320.0:
		_hook_cooldown = hook_cooldown_time
		_start_hook(player)
		return
	if _drag_delay <= 0.0 and to_player.length() > 90.0:
		_drag_delay = 7.0
		_start_drag()
		return

	_decision_left = maxf(0.0, _decision_left - delta)
	var desired := Vector2.ZERO
	if to_player.length() > combo_range - 8.0:
		desired = to_player.normalized() * walk_speed
	velocity = velocity.move_toward(desired, 600.0 * delta)
	move_and_slide()
	state = "walk" if desired != Vector2.ZERO else "idle"
	_play("walk" if desired != Vector2.ZERO else "stand")
	_refresh_bars()

# ---------------- 三连击 ----------------
func _start_combo(player: Node2D) -> void:
	state = "combo"
	_attack_target = player
	_combo_step = 0
	_combo_hit_done = false
	_combo_gap = 0.0
	velocity = Vector2.ZERO
	_play("combo")
	_play_sfx(attack_sfx)
	combos_done += 1

func _update_combo(delta: float, player: Node2D) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	_play("combo")
	var anim_len: float = _anim_len("combo_" + facing)
	var step_len: float = anim_len / 3.0
	_combo_gap += delta
	if _combo_step < 3 and _combo_gap >= step_len * float(_combo_step + 1):
		_combo_step += 1
		if player != null and player.global_position.distance_to(global_position) <= combo_range + 16.0:
			if player.has_method("try_take_hit"):
				player.try_take_hit(combo_damage, global_position)
	if _combo_gap >= anim_len:
		state = "idle"
		_combo_step = 0
		_decision_left = decision_interval
	_refresh_bars()

# ---------------- 格挡 / 反击 ----------------
func _start_block() -> void:
	state = "block"
	_blocking = true
	_state_left = block_seconds
	velocity = Vector2.ZERO
	_play("block")

func _update_block(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	_play("block")
	_state_left -= delta
	if _state_left <= 0.0:
		_blocking = false
		state = "idle"
		_decision_left = decision_interval
	_refresh_bars()

func _start_counter() -> void:
	state = "counter_windup"
	_blocking = false
	_state_left = counter_windup
	velocity = Vector2.ZERO
	_play("block_counter")
	sprite.pause()
	sprite.frame = 0
	counters_done += 1
	queue_redraw()

func _update_counter_windup(delta: float) -> void:
	velocity = Vector2.ZERO
	_play("block_counter")
	sprite.pause()
	sprite.frame = 0
	_state_left -= delta
	if _state_left <= 0.0:
		state = "counter"
		_state_left = 0.3
		sprite.play()
		_play_sfx(counter_sfx)
	queue_redraw()

func _update_counter(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	_state_left -= delta
	var player := _find_player()
	if player != null and _state_left <= 0.15 and _state_left + delta > 0.15:
		var to_player: Vector2 = player.global_position - global_position
		if to_player.length() <= combo_range + 26.0 and facing_dir().dot(to_player.normalized()) >= 0.0:
			if player.has_method("try_take_hit"):
				player.try_take_hit(counter_damage, global_position)
	if _state_left <= 0.0:
		state = "idle"
		_decision_left = decision_interval
	_refresh_bars()

# ---------------- 拖刀冲刺 ----------------
func _start_drag() -> void:
	state = "drag"
	_play_sfx(drag_sfx)
	_drag_phase = 0
	_state_left = 0.0
	drags_done += 1

func _update_drag(delta: float, player: Node2D) -> void:
	if _state_left <= 0.0:
		_state_left = float(7) / 14.0   # 拖刀行走播约 0.5 秒
	var dir: Vector2 = (player.global_position - global_position).normalized()
	velocity = dir * drag_speed
	move_and_slide()
	_play("drag_walk")
	_state_left -= delta
	if _state_left <= 0.0:
		state = "drag_slash"
		_state_left = 0.4
		velocity = Vector2.ZERO
		_play("drag_slash")

func _update_drag_slash(delta: float, player: Node2D) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	var half: float = _state_left
	_state_left -= delta
	if half > 0.18 and _state_left <= 0.18 and player != null:
		if player.global_position.distance_to(global_position) <= combo_range + 24.0:
			if player.has_method("try_take_hit"):
				player.try_take_hit(drag_damage, global_position)
	if _state_left <= 0.0:
		state = "idle"
		_decision_left = decision_interval
		_drag_delay = 7.0
	_refresh_bars()

# ---------------- 钩爪（吸血 < 50 触发一次）----------------
func _start_hook(player: Node2D) -> void:
	state = "hook"
	_hook_pull_done = false
	_state_left = 0.6
	velocity = Vector2.ZERO
	_play("hook_throw")
	hooks_done += 1

func _update_hook(delta: float, player: Node2D) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	_state_left -= delta
	if _state_left <= 0.0 and not _hook_pull_done:
		_hook_pull_done = true
		if player != null:
			# 把玩家拉到面前
			var front: Vector2 = global_position + facing_dir() * 34.0
			player.global_position = front
			if player.has_method("_start_hurt"):
				player.call("_start_hurt")
		# 接三连击
		state = "combo"
		_combo_step = 0
		_combo_gap = 0.0
		_combo_hit_done = false
		_play("combo")
	_refresh_bars()

# ---------------- 受击 ----------------
func take_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	# 格挡成功后先预警，再执行反击。
	if _blocking:
		blocked_hits += 1
		_play("block")
		_start_counter()
		_refresh_bars()
		return
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		_die()
	_refresh_bars()

## 韧性只由玩家反击削减
func damage_poise(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	poise = maxf(0.0, poise - amount)
	if poise <= 0.0:
		_stagger_left = stagger_seconds
		state = "stagger"
		velocity = Vector2.ZERO
		_play("stagger")
		await get_tree().create_timer(_anim_len("stagger_" + facing), false).timeout
		if not dead:
			poise = poise_max
	_refresh_bars()

func stun(seconds: float) -> void:
	if dead:
		return
	stun_left = maxf(stun_left, seconds)
	velocity = Vector2.ZERO
	if state == "counter_windup":
		state = "idle"
		_decision_left = decision_interval
		queue_redraw()

func _die() -> void:
	if dead:
		return
	dead = true
	dead_left = corpse_seconds
	state = "die"
	velocity = Vector2.ZERO
	_play("stagger")
	modulate = Color(0.55, 0.55, 0.6, 0.85)
	if bars != null:
		bars.visible = false
	var col: CollisionShape2D = get_node_or_null("Collision")
	if col != null:
		col.set_deferred("disabled", true)
	defeated.emit()

# ---------------- 工具 ----------------
func facing_dir() -> Vector2:
	var idx := DIRS.find(facing)
	if idx < 0:
		idx = 0
	var deg: float = idx * 45.0
	return Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg)))

func _face(v: Vector2) -> void:
	if v.length() < 0.001:
		return
	var deg := rad_to_deg(v.angle())
	facing = DIRS[int(round(fposmod(deg, 360.0) / 45.0)) % 8]

func _play(anim: String) -> void:
	var full := anim + "_" + facing
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(full):
		full = anim + "_S"
	if sprite.animation != full:
		sprite.play(full)

func _anim_len(anim: String) -> float:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim):
		return 0.5
	var fps: float = sprite.sprite_frames.get_animation_speed(anim)
	var cnt: int = sprite.sprite_frames.get_frame_count(anim)
	if fps <= 0.0:
		fps = 10.0
	return float(cnt) / fps

func _play_sfx(player: AudioStreamPlayer) -> void:
	if player != null and player.stream != null:
		player.play()

func _refresh_bars() -> void:
	if bars != null and bars.visible:
		bars.queue_redraw()
	queue_redraw()

func _draw() -> void:
	if state != "counter_windup" or dead or stun_left > 0.0 or _stagger_left > 0.0:
		return
	var progress := clampf(1.0 - _state_left / maxf(counter_windup, 0.001), 0.0, 1.0)
	var warning := Color(1.0, 0.55, 0.12)
	draw_arc(Vector2(0, -6), 34, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, warning, 3.0, true)
	var marker := Vector2(0, -98)
	draw_circle(marker, 12, Color(0.08, 0.04, 0.02, 0.95))
	draw_arc(marker, 12, 0, TAU, 32, warning, 2.0, true)
	draw_string(ThemeDB.fallback_font, marker + Vector2(-3.5, 6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, warning)

func _find_player() -> Node2D:
	var p := get_parent()
	if p != null:
		var n := p.get_node_or_null("Player")
		if n is Node2D:
			return n
	return null
