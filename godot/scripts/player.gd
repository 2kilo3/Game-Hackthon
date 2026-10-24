extends CharacterBody2D
## 8 方向像素角色：移动、朝向吸附、站立/移动动画状态机 + Shift 闪避 + 体力。
##
## 设计要点：
##   1. 有移动输入就绝不切站立帧；只有输入松开且速度归零才站定。
##   2. 帧率与地速成正比：fps = 速度 × fps_per_speed，每帧前进距离恒定，不打滑。
##   3. 停步后继续播完 run_out_seconds 的移动动画，避免定格在腾空姿势。
##   4. Shift = 闪避：0.5 秒判定窗口，方向锁死、速度曲线冲刺、期间无敌。
##      闪避时**统一定格在移动动画第 0 帧**，不再播完整套跑动帧。
##   5. 体力：上限 10，闪避消耗 2；5 秒不闪避后每秒回复 1 点。

## 屏幕角度 → 方向名（0° = 右，90° = 下）
const DIRS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

@export_group("移动")
@export var walk_speed := 118.0
@export var accel := 1500.0
@export var decel := 2000.0

@export_group("闪避")
## 闪避判定持续时间（秒）
@export var dodge_duration := 0.5
## 闪避起始冲刺速度
@export var dodge_speed := 520.0
## 闪避结束时的速度（缓出到接近走路速度）
@export var dodge_end_speed := 130.0
## 闪避结束后的冷却时间（秒）
@export var dodge_cooldown := 0.2
## 闪避期间是否无敌
@export var dodge_invulnerable := true

@export_group("极限闪避")
## 闪避开始后多久内被攻击命中算「极限闪避」（秒）
@export var perfect_window := 0.18
## 触发极限闪避回复的体力
@export var perfect_stamina_gain := 40.0
## 时缓倍率（越小越慢；0.18 是"明显变慢"的强度）
@export var perfect_time_scale := 0.18
## 时缓持续时间（真实时间，秒）
@export var perfect_slow_seconds := 0.6
## 时缓里保持最慢的占比（剩下的时间平滑恢复到正常速度）
@export var perfect_slow_hold_ratio := 0.6

@export_group("普攻")
## 一次普攻造成的伤害
@export var attack_damage := 5.0
## 攻击距离（世界像素）
@export var attack_range := 58.0
## 目标必须在朝向的多少度以内（点积阈值，0.3 约 ±72°）
@export var attack_facing_dot := 0.3
## 在动画的哪个进度判定命中（0.45 = 45%）
@export var attack_hit_ratio := 0.45
@export_group("体力")
## 体力上限
@export var stamina_max := 100.0
## 每次闪避消耗
@export var dodge_cost := 20.0
## 停止闪避多久后开始回复（秒）
@export var stamina_regen_delay := 5.0
## 回复速度（点/秒）
@export var stamina_regen_rate := 1.0
## 恢复间隔（秒）：默认每 0.1s 回 1 点
@export var stamina_regen_interval := 0.1

@export_group("格挡")
## 格挡成功时受到的伤害倍率（0.5 = 伤害降低 50%）
@export var block_damage_multiplier := 0.5
## 格挡成功时受到的击退倍率
@export var block_knockback_multiplier := 0.5
## 每次格挡成功消耗的韧性
@export var block_poise_cost := 10.0
## 格挡时背部受击额外削减的韧性
@export var block_back_poise_cost := 20.0
## 格挡成功时的顿帧时长（真实时间，秒）
@export var block_hitstop_seconds := 0.1
## 顿帧时的时间倍率（越小越"定住"，0.02 接近完全定格）
@export var block_hitstop_time_scale := 0.02
@export_group("格挡体力")
## 开始格挡时消耗的体力（不足 10 点就归零）
@export var block_stamina_cost := 10.0
## 保持格挡时每次消耗的体力
@export var block_stamina_drain := 1.0
## 保持格挡的体力消耗间隔（秒）
@export var block_stamina_drain_interval := 0.2

@export_group("完美格挡 / 力竭")
## 完美格挡（抬手期间被击中）恢复的韧性
@export var perfect_block_poise_gain := 30.0
## 完美格挡动画时长（秒），期间除主角外全部时停
@export var perfect_block_seconds := 0.6
## 完美格挡音效从第几秒开始播（素材的爆发点在后面，跳过前面的铺垫）
@export var perfect_block_sfx_offset := 0.7
## 完美格挡回复的体力
@export var perfect_block_stamina_gain := 10.0
## 韧性清空后进入「力竭」的持续时间（秒）
@export var exhaust_seconds := 10.0
## 力竭期间的移动速度倍率（0.8 = 减速 20%）
@export var exhaust_speed_multiplier := 0.8

@export_group("连击")
## 二段普攻（上挑）伤害
@export var attack2_damage := 8.0
## 三段普攻（短冲刀光）伤害
@export var attack3_damage := 12.0
## 三段普攻向前突进的速度（px/s，0 = 不突进）
@export var attack3_dash_speed := 300.0
## 三段普攻突进持续时间（秒），约等于位移 = speed × time
@export var attack3_dash_time := 0.12
## 从第几段开始可以接受下一段的输入（0~1，占动画比例）
@export var combo_chain_ratio := 0.3
## 输出每段的动画时长（秒），对应 tools/gen_frames_tres.js 里的 0.45 / 0.55
@export var attack2_seconds := 0.45
@export var attack3_seconds := 0.55

@export_group("反击")
## 完美格挡后的反击伤害
@export var counter_damage := 20.0
## 钩爪：冷却 5 秒、射程 260、眩晕 0.5 秒
@export var claw_cooldown := 5.0
@export var claw_range := 260.0
@export var claw_stun_seconds := 1.0
## 反击削减的韧性（破除后目标会瘫痪，见 test_dummy / shooter_dummy 的 poise_break_seconds）
@export var counter_poise_damage := 20.0
## 反击范围（世界像素，从角色到目标边缘算）
@export var counter_range := 120.0
## 反击朝向判定（点积）
@export var counter_facing_dot := 0.3
## 反击判定在动画的哪个进度
@export var counter_hit_ratio := 0.45
## 反击能清掉的子弹半径
@export var counter_bullet_radius := 130.0

@export_group("生命")
## 生命上限
@export var hp_max := 40.0
## 受击后的无敌时间（秒），避免一帧多次判定
@export var hurt_invulnerable := 0.4

@export_group("韧性")
## 韧性上限（留给之后的格挡/破防系统）
@export var poise_max := 100.0

@export_group("动画")
## SpriteFrames 里移动动画的基准速度（fps）
@export var anim_base_speed := 10.0
## fps = 速度 × 该系数
@export var fps_per_speed := 0.085
@export var fps_min := 9.0
@export var fps_max := 20.0
## 松手后继续播放移动动画的时长（秒）
@export var run_out_seconds := 0.28
## 速度低于该值视为站定
@export var stand_speed_threshold := 12.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var shadow: Node2D = $Shadow
@onready var run_sfx: AudioStreamPlayer = $RunSfx
@onready var block_sfx: AudioStreamPlayer = $BlockSfx
@onready var perfect_block_sfx: AudioStreamPlayer = $PerfectBlockSfx
@onready var dodge_sfx: AudioStreamPlayer = $DodgeSfx
@onready var perfect_dodge_sfx: AudioStreamPlayer = $PerfectDodgeSfx
@onready var attack_sfx: AudioStreamPlayer = $AttackSfx
@onready var counter_sfx: AudioStreamPlayer = $CounterSfx
@onready var respawn_sfx: AudioStreamPlayer = $RespawnSfx
@onready var death_sfx: AudioStreamPlayer = $DeathSfx
@onready var era_switch_sfx: AudioStreamPlayer = $EraSwitchSfx
@onready var era_appear_sfx: AudioStreamPlayer = $EraAppearSfx
@onready var hit_sfx: AudioStreamPlayer = $HitSfx
@onready var afterimage: Node2D = $Afterimage

## 触发极限闪避时发出（世界/UI 可以接这个做提示）
signal perfect_dodge
## 触发完美格挡（时停开始）
signal perfect_block_started
## 力竭开始 / 结束
signal exhausted_started
signal exhausted_finished
## 倒地动画播完（world 收到后才开始黑屏回溯）
signal death_animation_finished
## 变换时空：消失播完的那一刻（world 收到后真正切换时空）
signal era_shift_midpoint
signal talents_changed
signal claw_unlocked

var facing := "S"
var facing_angle := 90.0
var state := "stand"          # stand | move | runout | dodge
var run_out := 0.0
var speed := 0.0

# --- 闪避状态 ---
var dodge_time := 0.0
var dodge_cooldown_left := 0.0
var dodge_dir := Vector2.ZERO
var dodge_frame := 0
var facing_dir := Vector2.DOWN
var invulnerable := false
var attack_time := 0.0
var attack_duration := 0.4
var attack_hit_done := false
var attack_hit_something := false
var combo_step := 1          # 当前是第几段（1/2/3）
var combo_queued := false    # 是否已缓存下一段输入
var attack_dash_left := 0.0  # 三段普攻剩余突进时间
var dying := false           # 正在播放倒地动画
var era_shift_phase := ""    # "" | vanish | appear
var era_shift_time := 0.0
var era_side := "right"      # 用左变换还是右变换（按朝向）
var death_time := 0.0
var death_finished := false
var block_phase := "in"     # in | hold | out | hit
var perfect_block_used := false   # 这次格挡是否已经触发过完美格挡
var perfect_block_time := 0.0
var exhaust_left := 0.0           # >0 表示力竭中
var _hitstop_until_ms := 0        # 格挡顿帧结束的墙钟时间（ms），0 表示没有顿帧
var counter_time := 0.0
var counter_hit_done := false
var _block_drain_acc := 0.0
var block_time := 0.0
var perfect_used := false     # 本次闪避是否已经触发过极限闪避
var _slow_left := 0.0          # 时缓剩余真实时间
var _slow_total := 0.0

# --- 体力 ---
var stamina := 100.0
var _stamina_regen_acc := 0.0
var time_since_stamina_use := 999.0   # 距离上次"用体力"（闪避/格挡）的时间

# --- 生命 / 韧性 ---
var hp := 40.0
var poise := 100.0
var hurt_invuln_left := 0.0
## 受击硬直剩余时间（播放 hit_<方向> 动画）
var hurt_anim_left := 0.0
## 钩爪技能（拾取现代 boss 掉落的道具后解锁）
var has_claw := false
var claw_cooldown_left := 0.0
var claw_anim_left := 0.0
var _claw_to := Vector2.ZERO
var _claw_from := Vector2.ZERO
var claw_uses := 0
## 镜头短暂聚焦（boss 出场用）：聚焦目标 + 剩余时间
var cam_focus_pos := Vector2.ZERO
var cam_focus_left := 0.0
var cam_focus_target: Node2D
var _cam_focus_center := Vector2.ZERO
var talent_points := 0
var talent_health := 0
var talent_attack := 0
var talent_defense := 0
var _base_hp_max := 40.0
var _health_regen_elapsed := 0.0

func _ready() -> void:
	_base_hp_max = hp_max
	stamina = stamina_max
	hp = hp_max
	poise = poise_max
	sprite.play("stand_" + facing)
	afterimage.setup(sprite, get_parent())
	# 跑步音效是一段循环素材，运行时标记循环（不用改导入设置）
	if run_sfx.stream is AudioStreamMP3:
		(run_sfx.stream as AudioStreamMP3).loop = true

func _physics_process(delta: float) -> void:
	if not get_tree().paused:
		_update_camera_focus(delta)
		_update_talent_regen(delta)
		if not is_dead():
			claw_cooldown_left = maxf(0.0, claw_cooldown_left - delta)
	if dodge_cooldown_left > 0.0:
		dodge_cooldown_left = maxf(0.0, dodge_cooldown_left - delta)
	if hurt_invuln_left > 0.0:
		hurt_invuln_left = maxf(0.0, hurt_invuln_left - delta)
	_update_exhaust(delta)
	# 顿帧计时必须每帧都跑（哪怕在倒地），否则 time_scale 卡在 0.02 会变成超长慢放
	_update_hitstop(delta)

	# ---- 倒地：只播动画，不接受输入 ----
	if state == "dying":
		_update_death(delta)
		return
	# ---- 变换时空：消失 → （world 切时空）→ 倒放出现 ----
	if state == "era_shift":
		_update_era_shift(delta)
		return

	# ---- 钩爪技能：拾取后可用，冷却 5 秒 ----
	if claw_anim_left > 0.0:
		claw_anim_left = maxf(0.0, claw_anim_left - delta)
		queue_redraw()
	if has_claw and Input.is_action_just_pressed("claw") and claw_cooldown_left <= 0.0:
		_fire_claw()

	# ---- 受击硬直：只播受击动画，暂时不吃输入 ----
	if state == "hurt":
		hurt_anim_left = maxf(0.0, hurt_anim_left - delta)
		velocity = velocity.move_toward(Vector2.ZERO, decel * delta)
		move_and_slide()
		if hurt_anim_left <= 0.0:
			state = "stand"
		_update_animation()
		return

	_update_stamina(delta)

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var moving := input.length() > 0.01
	if moving:
		facing_dir = input.normalized()

	# ---- 完美格挡：时停期间只推进自己的动画 ----
	if state == "perfect_block":
		perfect_block_time += delta
		if perfect_block_time >= _anim_duration("perfect_block_" + facing):
			_end_perfect_block()
		_update_animation()
		shadow.speed_ratio = 1.0
		return

	# ---- 动作优先级：闪避（可取消一切）> 闪避中 > 格挡 > 普攻 > 普通移动 ----
	var want_block := Input.is_action_pressed("block")
	if state != "dodge" and Input.is_action_just_pressed("dodge") and _can_dodge():
		_start_dodge(input, moving)
	elif state == "dodge":
		_update_dodge(delta)
	elif state == "block":
		_update_block(delta, want_block)
	elif state == "counter":
		_update_counter(delta)
	elif want_block and _can_block():
		_start_block()
	elif state == "attack":
		_update_attack(delta)
	elif Input.is_action_just_pressed("attack") and _can_attack():
		_start_attack()
	else:
		# ---- 普通移动（力竭时减速）----
		var rate := accel if moving else decel
		var target_speed: float = walk_speed * (exhaust_speed_multiplier if is_exhausted() else 1.0)
		velocity = velocity.move_toward(input * target_speed, rate * delta)
		move_and_slide()
		speed = velocity.length()
		if not moving and speed < 3.0:
			velocity = Vector2.ZERO
			speed = 0.0

	# ---- 朝向：按输入方向吸附到 8 方向（闪避 / 普攻 / 格挡中锁定）----
	if moving and state != "dodge" and state != "attack" and state != "block" and state != "counter":
		facing_angle = rad_to_deg(atan2(input.y, input.x))
		facing = _dir_from_angle(facing_angle)

	# ---- 状态机（闪避 / 普攻 / 格挡之外）----
	if state != "dodge" and state != "attack" and state != "block" and state != "counter":
		var wants_move := moving or speed > stand_speed_threshold
		if wants_move:
			state = "move"
			run_out = 0.0
		elif state == "move":
			state = "runout"
			run_out = 0.0

		if state == "runout":
			run_out += delta
			if run_out >= run_out_seconds:
				state = "stand"

	# ---- 动画 / 阴影 / 音效 ----
	_update_animation()
	_update_run_sfx()
	shadow.speed_ratio = clampf(speed / walk_speed, 0.0, 1.0) if state != "dodge" else 1.0

# ---------------- 格挡 ----------------
func _can_block() -> bool:
	return not is_dead() and state != "attack" and state != "dodge" and stamina > 0.0

func _block_anim(seg: String) -> String:
	return "block_%s_%s" % [seg, facing]

func _start_block() -> void:
	state = "block"
	block_phase = "in"
	block_time = 0.0
	perfect_block_used = false
	_block_drain_acc = 0.0
	# 起手消耗 10 点体力（不足就归零）
	stamina = maxf(0.0, stamina - block_stamina_cost)
	velocity = Vector2.ZERO
	speed = 0.0
	sprite.play(_block_anim("in"))

# ---------------- 完美格挡（抬手期间被击中） ----------------
## 触发完美格挡：免伤 + 回 30 韧性 + 除主角外全部时停，直到动画播完
func _start_perfect_block() -> void:
	state = "perfect_block"
	perfect_block_used = true
	perfect_block_time = 0.0
	block_phase = "in"
	block_time = 0.0
	velocity = Vector2.ZERO
	speed = 0.0
	poise = minf(poise_max, poise + perfect_block_poise_gain)
	stamina = minf(stamina_max, stamina + perfect_block_stamina_gain)
	sprite.play("perfect_block_" + facing)
	_play_perfect_block_sfx()
	# 时停：暂停整棵树，只让主角自己继续跑（process_mode = ALWAYS）
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	perfect_block_started.emit()

func _end_perfect_block() -> void:
	get_tree().paused = false
	process_mode = Node.PROCESS_MODE_INHERIT
	perfect_block_time = 0.0
	block_phase = "in"
	block_time = 0.0
	# 完美格挡后立刻反击
	_start_counter()

func is_in_perfect_block() -> bool:
	return state == "perfect_block"

# ---------------- 反击（完美格挡后触发） ----------------
func _counter_anim() -> String:
	return "counter_" + facing

func _counter_side_anim() -> String:
	return "counter_" + facing

func _start_counter() -> void:
	state = "counter"
	counter_time = 0.0
	counter_hit_done = false
	velocity = Vector2.ZERO
	speed = 0.0
	sprite.play(_counter_anim())
	_clear_bullets_in_range()

func _update_counter(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, decel * 2.0 * delta)
	move_and_slide()
	speed = velocity.length()
	counter_time += delta
	var dur := _anim_duration(_counter_anim())
	# 反击命中：清掉范围内子弹 + 对正前方的目标造成 20 点伤害
	if not counter_hit_done and counter_time >= dur * counter_hit_ratio:
		counter_hit_done = true
		_do_counter_hit()
	if counter_time >= dur:
		counter_time = 0.0
		if Input.is_action_pressed("block") and stamina > 0.0 and _can_block():
			state = "block"
			block_phase = "hold"
			block_time = 0.0
			sprite.play(_block_anim("hold"))
		else:
			state = "stand"
			block_phase = "in"
			block_time = 0.0

func _counter_face_vec() -> Vector2:
	var face_vec := facing_dir.normalized()
	if face_vec == Vector2.ZERO:
		face_vec = Vector2.DOWN
	return face_vec

func _do_counter_hit() -> void:
	# 反击音效放在刀光真正打出去的那一帧，和"完美格挡"的音效分开
	_play_counter_sfx()
	_clear_bullets_in_range()
	var face_vec := _counter_face_vec()
	var layer := get_parent()
	if layer == null:
		return
	for child in layer.get_children():
		if child == self or not (child is Node2D):
			continue
		if not child.has_method("take_damage"):
			continue
		# 另一个时空的实体是隐藏的，不能被当前时空的攻击打到
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		var to_target: Vector2 = child.global_position - global_position
		if to_target.length() < 0.001:
			continue
		# 用"到目标边缘"的距离判定，和刀光实际长度对得上（粗柱子/木箱也能刮到）
		if _edge_distance(child) > counter_range:
			continue
		if face_vec.dot(to_target.normalized()) < counter_facing_dot:
			continue
		child.take_damage(counter_damage)
		# 反击同时削韧性：削空后目标会进入瘫痪（见 dummy 的 poise_break_seconds）
		if child.has_method("damage_poise"):
			child.damage_poise(counter_poise_damage)

## 到目标碰撞盒（矩形）边缘的距离；没有碰撞盒就用中心距离
func _edge_distance(target: Node2D) -> float:
	var to_target: Vector2 = (target.global_position - global_position).abs()
	var half := Vector2.ZERO
	var col := target.get_node_or_null("Collision")
	if col is CollisionShape2D and col.shape is RectangleShape2D:
		half = (col.shape as RectangleShape2D).size * 0.5
	var outside := (to_target - half).max(Vector2.ZERO)
	return outside.length()

## 反击顺手清掉范围内的远程子弹
func _clear_bullets_in_range() -> void:
	var layer := get_parent()
	if layer == null:
		return
	for child in layer.get_children():
		if not (child is Node2D):
			continue
		if not child.has_method("is_bullet") or not child.is_bullet():
			continue
		if child.global_position.distance_to(global_position) <= counter_bullet_radius:
			child.destroy_bullet()

# ---------------- 力竭 ----------------

# ---------------- 力竭 ----------------
func is_exhausted() -> bool:
	return exhaust_left > 0.0

func exhaust_ratio() -> float:
	return clampf(exhaust_left / maxf(0.01, exhaust_seconds), 0.0, 1.0)

func _update_exhaust(delta: float) -> void:
	if exhaust_left <= 0.0:
		return
	exhaust_left = maxf(0.0, exhaust_left - delta)
	if exhaust_left <= 0.0:
		# 效果结束：韧性重新充满
		poise = poise_max
		exhausted_finished.emit()

func _start_exhaust() -> void:
	if exhaust_left > 0.0:
		return
	exhaust_left = exhaust_seconds
	exhausted_started.emit()

func _update_block(delta: float, want_block: bool) -> void:
	# 格挡时站定（轻微刹停）
	velocity = velocity.move_toward(Vector2.ZERO, decel * 2.0 * delta)
	move_and_slide()
	speed = velocity.length()

	# 保持格挡持续消耗体力：每 0.2s 扣 1 点；没体力就撑不住
	_block_drain_acc += delta
	while _block_drain_acc >= block_stamina_drain_interval:
		_block_drain_acc -= block_stamina_drain_interval
		stamina = maxf(0.0, stamina - block_stamina_drain)
	if stamina <= 0.0 and block_phase != "out":
		block_phase = "out"
		block_time = 0.0
		sprite.play(_block_anim("out"))

	match block_phase:
		"in":
			block_time += delta
			if block_time >= _anim_duration(_block_anim("in")):
				block_time = 0.0
				if want_block:
					block_phase = "hold"
					sprite.play(_block_anim("hold"))
				else:
					block_phase = "out"
					sprite.play(_block_anim("out"))
		"hold":
			if not want_block:
				block_phase = "out"
				block_time = 0.0
				sprite.play(_block_anim("out"))
		"hit":
			# 被打中的火花反应播完之后回到保持（还按着 K）或放下
			block_time += delta
			if block_time >= _anim_duration(_block_anim("hit")):
				block_time = 0.0
				if want_block:
					block_phase = "hold"
					sprite.play(_block_anim("hold"))
				else:
					block_phase = "out"
					sprite.play(_block_anim("out"))
		"out":
			block_time += delta
			if block_time >= _anim_duration(_block_anim("out")):
				state = "stand"
				block_phase = "in"
				block_time = 0.0

## 格挡覆盖的半边：左右各 180°（朝右的素材挡右半圈，朝左的挡左半圈）
func block_side() -> Vector2:
	match facing:
		"W", "NW", "SW":
			return Vector2.LEFT
		_:
			return Vector2.RIGHT

## 某个来源方向是否落在格挡的一侧（180°）
func is_attack_blocked(source_pos: Vector2) -> bool:
	if state != "block":
		return false
	var to_source := source_pos - global_position
	if to_source.length() < 0.001:
		return true   # 贴在身上打，算挡下
	return block_side().dot(to_source.normalized()) >= 0.0

## 格挡中受到的伤害倍率（给攻击方/UI 查询；不看方向，只看是否在格挡状态）
func damage_multiplier() -> float:
	return block_damage_multiplier if state == "block" else 1.0

## 当前是否在格挡（含抬起/放下动作期间）
func is_blocking() -> bool:
	return state == "block"

## 格挡成功时的顿帧：把时间压到很慢一小段（真实时间计时，必定恢复）
func _apply_block_hitstop() -> void:
	if _slow_left > 0.0:
		return   # 时缓（极限闪避）优先，避免两套时间缩放打架
	# 连续挨打时刷新计时，而不是叠加多个定时器
	_hitstop_until_ms = Time.get_ticks_msec() + int(block_hitstop_seconds * 1000.0)
	Engine.time_scale = block_hitstop_time_scale

## 顿帧倒计时：用墙钟时间，和 time_scale / 物理帧缩放都无关，必定按时恢复
func _update_hitstop(_delta: float) -> void:
	# 已经死了就立刻收掉顿帧，别让死亡演出被慢放拖住
	if dying:
		_hitstop_until_ms = 0
		if not get_tree().paused and Engine.time_scale < 1.0:
			Engine.time_scale = 1.0
		return
	if _hitstop_until_ms <= 0:
		return
	if _slow_left > 0.0:
		# 时缓接管：让时缓自己恢复正常速度
		_hitstop_until_ms = 0
		return
	if Time.get_ticks_msec() >= _hitstop_until_ms:
		_hitstop_until_ms = 0
		Engine.time_scale = 1.0
# ---------------- 普攻 ----------------
func _can_attack() -> bool:
	return state != "attack" and not is_dead()

func _start_attack() -> void:
	state = "attack"
	combo_step = 1
	combo_queued = false
	_play_attack_sfx()
	_begin_attack_stage()

## 播放当前连击段的动画并重置计时
func _begin_attack_stage() -> void:
	attack_time = 0.0
	attack_hit_done = false
	attack_hit_something = false
	velocity = Vector2.ZERO
	speed = 0.0
	# 三段普攻：向前突进一小段（"短冲刀光"）
	attack_dash_left = 0.0
	if combo_step == 3 and attack3_dash_speed > 0.0 and attack3_dash_time > 0.0:
		attack_dash_left = attack3_dash_time
		var dir := facing_dir.normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		velocity = dir * attack3_dash_speed
	var anim := _attack_anim()
	attack_duration = _anim_duration(anim)
	sprite.play(anim)

## 当前连击段的动画名：attack_<dir> / attack2_<dir> / attack3_<dir>
func _attack_anim() -> String:
	if combo_step <= 1:
		return "attack_" + facing
	return "attack%d_%s" % [combo_step, facing]

## 当前连击段的伤害
func _attack_damage() -> float:
	match combo_step:
		2:
			return attack2_damage + talent_attack_bonus()
		3:
			return attack3_damage + talent_attack_bonus()
		_:
			return attack_damage + talent_attack_bonus()

func _update_attack(delta: float) -> void:
	attack_time += delta
	# 三段普攻前段保持突进速度，其余时间刹停
	if attack_dash_left > 0.0:
		attack_dash_left = maxf(0.0, attack_dash_left - delta)
		var dir := facing_dir.normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		velocity = dir * attack3_dash_speed
	else:
		velocity = velocity.move_toward(Vector2.ZERO, decel * 2.0 * delta)
	move_and_slide()
	speed = velocity.length()

	# 连击输入：动画过了一定进度后按 J 会缓存下一段
	if Input.is_action_just_pressed("attack") and combo_step < 3 and attack_time >= attack_duration * combo_chain_ratio:
		combo_queued = true

	# 命中窗口：动画 45% 处判定一次
	if not attack_hit_done and attack_time >= attack_duration * attack_hit_ratio:
		attack_hit_done = true
		_do_attack_hit()

	if attack_time >= attack_duration:
		if combo_queued and combo_step < 3:
			# 接力下一段
			combo_step += 1
			combo_queued = false
			_play_attack_sfx()
			_begin_attack_stage()
		else:
			combo_step = 1
			combo_queued = false
			state = "stand"
			run_out = 0.0

func _do_attack_hit() -> void:
	var target := _find_attack_target()
	if target == null:
		return
	attack_hit_something = true
	# 普攻只削血，不削韧性（韧性留给格挡/破防系统）
	if target.has_method("take_damage"):
		target.take_damage(_attack_damage())

## 找攻击范围内的目标：朝向与距离都要满足
func _find_attack_target() -> Node2D:
	var layer := get_parent()
	if layer == null:
		return null
	var face_vec := facing_dir.normalized()
	if face_vec == Vector2.ZERO:
		face_vec = Vector2.DOWN
	for child in layer.get_children():
		if child == self or not (child is Node2D):
			continue
		if not child.has_method("take_damage"):
			continue
		# 另一个时空的实体是隐藏的，不能被当前时空的攻击打到
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		var to_target: Vector2 = child.global_position - global_position
		if to_target.length() > attack_range:
			continue
		if face_vec.dot(to_target.normalized()) < attack_facing_dot:
			continue
		return child
	return null

## 动画时长 = 帧数 / 速度（普攻各方向帧数不同，时长被资源里的 speed 拉齐）
func _anim_duration(anim: String) -> float:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim):
		return 0.4
	var frames: int = sprite.sprite_frames.get_frame_count(anim)
	var spd: float = sprite.sprite_frames.get_animation_speed(anim)
	if spd <= 0.0:
		return 0.4
	return float(frames) / spd

# ---------------- 音效 ----------------
func _play_block_sfx() -> void:
	if block_sfx == null or block_sfx.stream == null:
		return
	block_sfx.stop()
	block_sfx.play()

func _play_perfect_block_sfx() -> void:
	if perfect_block_sfx == null or perfect_block_sfx.stream == null:
		return
	perfect_block_sfx.stop()
	# 从素材的爆发点开始播（不是从 0 秒的铺垫开始）
	perfect_block_sfx.play(maxf(0.0, perfect_block_sfx_offset))

func _play_dodge_sfx() -> void:
	if dodge_sfx == null or dodge_sfx.stream == null:
		return
	dodge_sfx.stop()
	dodge_sfx.play()

func _play_perfect_dodge_sfx() -> void:
	if perfect_dodge_sfx == null or perfect_dodge_sfx.stream == null:
		return
	perfect_dodge_sfx.stop()
	perfect_dodge_sfx.play()

func _play_respawn_sfx() -> void:
	if respawn_sfx == null or respawn_sfx.stream == null:
		return
	respawn_sfx.stop()
	respawn_sfx.play()

func _play_counter_sfx() -> void:
	if counter_sfx == null or counter_sfx.stream == null:
		return
	counter_sfx.stop()
	counter_sfx.play()

func _play_attack_sfx() -> void:
	if attack_sfx == null or attack_sfx.stream == null:
		return
	attack_sfx.stop()
	attack_sfx.play()

## 跑步音效：移动时循环播放，停下就停
func _update_run_sfx() -> void:
	if run_sfx == null or run_sfx.stream == null:
		return
	var should_play: bool = state == "move" and speed > 20.0
	if should_play and not run_sfx.playing:
		run_sfx.play()
	elif not should_play and run_sfx.playing:
		run_sfx.stop()

# ---------------- 体力 ----------------

# ---------------- 体力 ----------------
func _update_stamina(delta: float) -> void:
	time_since_stamina_use += delta
	# 格挡 / 反击 / 完美格挡期间：算"正在使用体力"，计时清零且不回体力
	if state == "block" or state == "counter" or state == "perfect_block":
		time_since_stamina_use = 0.0
		_stamina_regen_acc = 0.0
		return
	if time_since_stamina_use < stamina_regen_delay or stamina >= stamina_max:
		_stamina_regen_acc = 0.0
		return
	# 累积到 0.1s 就回 1 点（5 秒不闪避后按 10 点/秒恢复）
	_stamina_regen_acc += delta
	while _stamina_regen_acc >= stamina_regen_interval and stamina < stamina_max:
		_stamina_regen_acc -= stamina_regen_interval
		stamina = minf(stamina_max, stamina + stamina_regen_rate)
	if stamina >= stamina_max:
		_stamina_regen_acc = 0.0

func _can_dodge() -> bool:
	return dodge_cooldown_left <= 0.0 and stamina >= dodge_cost

func get_stamina_ratio() -> float:
	return clampf(stamina / stamina_max, 0.0, 1.0)

## 体力是否够下一次闪避（UI 用）
func can_afford_dodge() -> bool:
	return stamina >= dodge_cost

# ---------------- 生命 ----------------
## 扣血。返回是否真的造成伤害（闪避无敌 / 受击无敌 / 已死亡时返回 false）。
## 攻击方如果要区分「极限闪避」，请用 try_take_hit()。
func take_damage(amount: float) -> bool:
	if amount <= 0.0 or is_dead() or hurt_invuln_left > 0.0 or is_invulnerable():
		return false
	var damage := damage_after_defense(amount)
	if damage <= 0.0:
		return false
	hp = maxf(0.0, hp - damage)
	hurt_invuln_left = hurt_invulnerable
	return true

## 回血（不超过上限）
func heal(amount: float) -> void:
	hp = minf(hp_max, hp + maxf(0.0, amount))

func is_dead() -> bool:
	return hp <= 0.0

func get_hp_ratio() -> float:
	return clampf(hp / hp_max, 0.0, 1.0)

# ---------------- 韧性（留给格挡系统） ----------------
## 削减韧性（格挡/受击时调用），归零时可以触发破防
func damage_poise(amount: float) -> void:
	poise = clampf(poise - amount, 0.0, poise_max)
	if poise <= 0.0:
		_start_exhaust()

## 恢复韧性
func restore_poise(amount: float) -> void:
	poise = clampf(poise + amount, 0.0, poise_max)

func is_poise_broken() -> bool:
	return poise <= 0.0

func get_poise_ratio() -> float:
	return clampf(poise / poise_max, 0.0, 1.0)

# ---------------- 受击入口（攻击方统一调用） ----------------
## 攻击命中判定。返回：
##   "perfect" —— 闪避中且在 perfect_window 内：极限闪避（免伤 + 回体力 + 时缓）
##   "blocked" —— 闪避免伤（普通闪避，或本次已触发过极限闪避）
##   "blocked_hit" —— 被格挡的一侧命中：伤害减半 + 顿帧 + 火花
##   "immune"  —— 受击无敌帧 / 已死亡
##   "hit"     —— 正常吃到伤害
## source_pos 是攻击来源位置（用来判断是否在格挡的一侧）
func try_take_hit(amount: float, source_pos: Vector2 = Vector2.ZERO, bypass_block: bool = false) -> String:
	if is_dead():
		return "immune"
	if state == "era_shift":
		return "immune"   # 变换时空期间无敌
	if state == "perfect_block":
		return "blocked"   # 时停中是无敌的
	if is_invulnerable():
		if not perfect_used and dodge_time <= perfect_window:
			perfect_used = true
			_on_perfect_dodge()
			return "perfect"
		return "blocked"

	# 完美格挡：在抬手期间被打中
	if state == "block" and block_phase == "in" and not perfect_block_used:
		_start_perfect_block()
		return "perfect_block"

	# 力竭期间普通格挡不再减伤（按未格挡处理）
	var blocked := is_attack_blocked(source_pos) and not is_exhausted() and not bypass_block
	if blocked:
		# 格挡成功：不受受击无敌限制，连续攻击每一下都会掉血、扣韧性并重播火花
		hp = maxf(0.0, hp - damage_after_defense(maxf(0.0, amount) * block_damage_multiplier))
		damage_poise(block_poise_cost)
		if state == "block":
			_play_block_hit()
		_play_block_sfx()
		_apply_block_hitstop()
		return "blocked_hit"

	if hurt_invuln_left > 0.0:
		return "immune"
	# 格挡时背部受击：吃满伤害，另外削 20 点韧性
	if state == "block":
		damage_poise(block_back_poise_cost)
	hp = maxf(0.0, hp - damage_after_defense(amount))
	hurt_invuln_left = hurt_invulnerable
	_play_hit_sfx()
	_start_hurt()
	return "hit"

## 进入受击硬直：播 hit_<方向>（约 0.4 秒），期间不能操作
func _start_hurt() -> void:
	if state == "dying" or state == "era_shift" or state == "block" or state == "perfect_block" or state == "counter":
		return   # 格挡/完美格挡/反击中被打中不进受击硬直（各自有专门反应）
	state = "hurt"
	hurt_anim_left = 0.4
	sprite.play("hit_" + facing)
	sprite.set_frame_and_progress(0, 0.0)
	sprite.speed_scale = 1.0

func _play_hit_sfx() -> void:
	if hit_sfx != null and hit_sfx.stream != null:
		hit_sfx.play()

## 播放（或从头重播）格挡火花反应
func _play_block_hit() -> void:
	block_phase = "hit"
	block_time = 0.0
	var anim := _block_anim("hit")
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)
	# 已经在这个动画里也要从第一帧重新来，连续挨打才会"立刻重播"
	sprite.set_frame_and_progress(0, 0.0)

func _on_perfect_dodge() -> void:
	stamina = minf(stamina_max, stamina + perfect_stamina_gain)
	# 本次闪避后续残影改成金色
	afterimage.set_golden(true)
	_play_perfect_dodge_sfx()
	_apply_time_slow()
	perfect_dodge.emit()

## 时缓：前段保持很慢，后段平滑回到正常速度。
## 注意：_process 的 delta 会被 time_scale 缩放，所以用 delta / time_scale 换回真实时间。
func _apply_time_slow() -> void:
	_slow_total = maxf(0.01, perfect_slow_seconds)
	_slow_left = _slow_total
	Engine.time_scale = perfect_time_scale

func _process(delta: float) -> void:
	if _slow_left <= 0.0:
		return
	var real_delta: float = delta / maxf(0.001, Engine.time_scale)
	_slow_left = maxf(0.0, _slow_left - real_delta)
	var progress: float = 1.0 - _slow_left / _slow_total
	# 前 hold_ratio 保持最慢，之后 smoothstep 恢复
	var ramp: float = clampf((progress - perfect_slow_hold_ratio) / maxf(0.001, 1.0 - perfect_slow_hold_ratio), 0.0, 1.0)
	var eased: float = ramp * ramp * (3.0 - 2.0 * ramp)
	Engine.time_scale = lerpf(perfect_time_scale, 1.0, eased)
	if _slow_left <= 0.0:
		Engine.time_scale = 1.0

## 被击退：直接改写速度，物理每帧的加速会自然把它吸收掉（约 0.15s）
## from_dir 是"被推的方向"（从攻击来源指向玩家），格挡成功时才减半
func apply_knockback(from_dir: Vector2, speed: float) -> void:
	if from_dir.length() < 0.001:
		return
	var blocked := state == "block" and block_side().dot(-from_dir.normalized()) >= 0.0
	var kb: float = speed * (block_knockback_multiplier if blocked else 1.0)
	velocity = from_dir.normalized() * kb
	speed = velocity.length()

# ---------------- 变换时空 ----------------
## 开始变换：先在当前时空化作光点消失，消失播完发 era_shift_midpoint（world 在那时切时空），
## 然后同一套动画倒放出现，并播出现音效。
func start_era_shift() -> void:
	if state == "era_shift" or is_dead() or dying:
		return
	state = "era_shift"
	era_shift_phase = "vanish"
	era_shift_time = 0.0
	velocity = Vector2.ZERO
	speed = 0.0
	afterimage.set_active(false)
	# 朝左用左变换，其余用右变换
	era_side = "left" if facing_dir.x < -0.01 else "right"
	sprite.play("era_vanish_" + era_side)
	sprite.speed_scale = 1.0
	if era_switch_sfx.stream != null:
		era_switch_sfx.play()

func is_era_shifting() -> bool:
	return state == "era_shift"

func _update_era_shift(delta: float) -> void:
	era_shift_time += delta
	velocity = Vector2.ZERO
	move_and_slide()
	speed = 0.0
	shadow.speed_ratio = 1.0
	var dur: float = _anim_duration("era_vanish_" + era_side)
	if era_shift_phase == "vanish":
		if era_shift_time >= dur:
			era_shift_phase = "appear"
			era_shift_time = 0.0
			era_shift_midpoint.emit()   # 这一帧 world 才真正切换时空
			sprite.play("era_appear_" + era_side)
			sprite.speed_scale = 1.0
			if era_appear_sfx.stream != null:
				era_appear_sfx.play()
	else:
		if era_shift_time >= dur:
			era_shift_phase = ""
			state = "stand"
			sprite.play("stand_" + facing)

## 直接死亡（调试 / 剧情用）

## 直接死亡（调试 / 剧情用）
func kill() -> void:
	hp = 0.0

## 开始倒地：播倒地动画 + 音效，动画播完发 death_animation_finished
func start_death() -> void:
	if dying or not is_dead():
		return
	# 死亡要清掉所有时间特效（格挡顿帧 / 时缓 / 完美格挡暂停），否则演出被慢放拖很久
	_hitstop_until_ms = 0
	_slow_left = 0.0
	Engine.time_scale = 1.0
	if get_tree().paused:
		get_tree().paused = false
		process_mode = Node.PROCESS_MODE_INHERIT
	dying = true
	_reset_camera_focus()
	_health_regen_elapsed = 0.0
	death_time = 0.0
	death_finished = false
	state = "dying"
	velocity = Vector2.ZERO
	speed = 0.0
	afterimage.set_active(false)
	sprite.play("death")
	sprite.speed_scale = 1.0
	if death_sfx.stream != null:
		death_sfx.play()

func is_dying() -> bool:
	return dying

func _update_death(delta: float) -> void:
	death_time += delta
	velocity = Vector2.ZERO
	move_and_slide()
	speed = 0.0
	shadow.speed_ratio = 0.0
	if not death_finished and death_time >= _anim_duration("death"):
		death_finished = true
		death_animation_finished.emit()

## 在指定位置复活：清空速度、闪避、状态，回到站立
func respawn(at: Vector2) -> void:
	_reset_camera_focus()
	_health_regen_elapsed = 0.0
	global_position = at
	velocity = Vector2.ZERO
	speed = 0.0
	state = "stand"
	era_shift_phase = ""
	era_shift_time = 0.0
	if era_switch_sfx != null and era_switch_sfx.playing:
		era_switch_sfx.stop()
	if era_appear_sfx != null and era_appear_sfx.playing:
		era_appear_sfx.stop()
	dying = false
	death_time = 0.0
	death_finished = false
	if death_sfx != null and death_sfx.playing:
		death_sfx.stop()
	run_out = 0.0
	dodge_time = 0.0
	dodge_cooldown_left = 0.0
	invulnerable = false
	perfect_used = false
	perfect_block_used = false
	perfect_block_time = 0.0
	exhaust_left = 0.0
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false
	process_mode = Node.PROCESS_MODE_INHERIT
	block_phase = "in"
	block_time = 0.0
	Engine.time_scale = 1.0
	afterimage.set_active(false)
	hurt_invuln_left = 0.0
	reset_stats()
	sprite.play("stand_" + facing)
	# 复活音效：在全黑转场里响起，随后画面渐亮
	_play_respawn_sfx()

## 恢复全部状态（调试 / 重开用）
func reset_stats() -> void:
	hp = hp_max
	poise = poise_max
	stamina = stamina_max
	dodge_cooldown_left = 0.0
	time_since_stamina_use = 999.0
	hurt_invuln_left = 0.0
	invulnerable = false

# ---------------- 闪避 ----------------
func _start_dodge(input: Vector2, moving: bool) -> void:
	# 统一使用移动动画的第 0 帧：有些动作帧（尤其抬腿腾空的）不适合闪避姿势
	dodge_frame = 0

	state = "dodge"
	dodge_time = 0.0
	invulnerable = dodge_invulnerable
	perfect_used = false
	stamina = maxf(0.0, stamina - dodge_cost)
	time_since_stamina_use = 0.0
	_play_dodge_sfx()

	# 有输入就朝输入方向，否则朝当前面向
	dodge_dir = input.normalized() if moving else facing_dir.normalized()
	if dodge_dir == Vector2.ZERO:
		dodge_dir = Vector2.DOWN
	if moving:
		facing_angle = rad_to_deg(atan2(dodge_dir.y, dodge_dir.x))
		facing = _dir_from_angle(facing_angle)

	afterimage.set_golden(false)
	afterimage.set_active(true)

func _update_dodge(delta: float) -> void:
	dodge_time += delta
	var t := clampf(dodge_time / dodge_duration, 0.0, 1.0)
	# 缓出：起手快、收尾慢（ease out quad）
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	var spd := lerpf(dodge_speed, dodge_end_speed, eased)
	velocity = dodge_dir * spd
	move_and_slide()
	speed = velocity.length()

	if dodge_time >= dodge_duration:
		_end_dodge()

func _end_dodge() -> void:
	state = "stand"
	dodge_time = 0.0
	invulnerable = false
	dodge_cooldown_left = dodge_cooldown
	afterimage.set_active(false)
	# 保留一点惯性，避免闪避结束时骤停
	velocity = dodge_dir * dodge_end_speed

# ---------------- 动画 ----------------
func _update_animation() -> void:
	if state == "dodge":
		# 闪避：定格在 dodge_frame，不推进帧
		if sprite.animation != facing:
			sprite.play(facing)
		sprite.set_frame_and_progress(dodge_frame, 0.0)
		sprite.pause()
		sprite.speed_scale = 1.0
		return

	if state == "perfect_block" or state == "counter":
		return   # 这两段动画分别由 _start_perfect_block / _start_counter 播放
	if state == "block":
		# 格挡：抬起 -> 保持（循环）-> 放下，各阶段动画在资源里定好速度
		var want := _block_anim(block_phase)
		if sprite.animation != want:
			sprite.play(want)
			sprite.speed_scale = 1.0
		return

	if state == "attack":
		# 普攻：播放当前连击段的动画（不循环，速度由资源里的 speed 决定）
		var atk := _attack_anim()
		if sprite.animation != atk:
			sprite.play(atk)
			sprite.speed_scale = 1.0
		return

	if state == "era_shift":
		return   # 消失/出现的动画由 _update_era_shift 自己切

	if state == "dying":
		# 倒地动画只播一次，播完停在最后一帧
		if sprite.animation != "death":
			sprite.play("death")
			sprite.speed_scale = 1.0
		return

	if state == "hurt":
		# 受击：播放 hit_<方向>（不循环，播完由状态机切回站立）
		var hurt_anim := "hit_" + facing
		if sprite.animation != hurt_anim:
			sprite.play(hurt_anim)
			sprite.speed_scale = 1.0
		return

	if state == "stand":
		sprite.play("stand_" + facing)
		sprite.speed_scale = 1.0
		return

	# 从闪避恢复时重新播放
	if not sprite.is_playing():
		sprite.play(facing)
	sprite.play(facing)
	# 帧率随速度变化
	var fps := clampf(speed * fps_per_speed, fps_min, fps_max)
	sprite.speed_scale = fps / anim_base_speed

## 屏幕角度 → 八方向（0° = 右，90° = 下）
func _dir_from_angle(deg: float) -> String:
	var a := fposmod(deg, 360.0)
	var idx := int(round(a / 45.0)) % 8
	return DIRS[idx]

## 给外部（敌人/伤害判定）查询：当前是否处于闪避无敌帧
func is_invulnerable() -> bool:
	return invulnerable and state == "dodge"

# ---------------- 钩爪 ----------------
## 朝周围最近的敌人发射钩爪：拉到身边并眩晕
func _fire_claw() -> void:
	if not has_claw or claw_cooldown_left > 0.0 or is_dead() or get_tree().paused or state == "dying" or state == "era_shift":
		return
	var layer := get_parent()
	if layer == null:
		return
	var best: Node2D = null
	var best_d := claw_range + 1.0
	for child in layer.get_children():
		if child == self or not (child is Node2D) or not (child is CanvasItem):
			continue
		var c := child as Node2D
		if not c.visible:
			continue
		if not c.has_method("take_damage") or not c.has_method("stun"):
			continue
		if "dead" in c and bool(c.dead):
			continue
		var d: float = global_position.distance_to(c.global_position)
		if d <= claw_range and d < best_d:
			best = c
			best_d = d
	if best == null:
		claw_cooldown_left = 0.6   # 空放：短冷却，避免连按
		return
	claw_cooldown_left = claw_cooldown
	claw_uses += 1
	# 发射实体钩爪：飞过去 → 把敌人拉回来 + 眩晕 → 收回
	var hook_scene: PackedScene = load("res://scenes/claw_hook.tscn")
	var hook: Node2D = hook_scene.instantiate()
	hook.target = best
	hook.owner_actor = self
	hook.global_position = global_position + Vector2(0, -20)
	layer.add_child(hook)

func _draw() -> void:
	if claw_anim_left <= 0.0:
		return
	var f: Vector2 = _claw_from - global_position
	var tt: Vector2 = _claw_to - global_position
	var a: float = clampf(claw_anim_left / 0.3, 0.0, 1.0)
	draw_line(f, tt, Color(0.75, 0.72, 0.6, 0.9 * a), 2.0)
	draw_circle(tt, 5.0 * a, Color(0.85, 0.8, 0.65, 0.8 * a))

## 让镜头在 seconds 秒内偏向 world_pos（boss 出场特写）
func focus_camera_on(world_pos: Vector2, seconds: float, target: Node2D = null) -> void:
	cam_focus_target = target
	var cam: Camera2D = get_node_or_null("Camera")
	_cam_focus_center = cam.global_position if cam != null else global_position
	cam_focus_pos = world_pos
	cam_focus_left = maxf(0.0, seconds)

## 每帧把相机往聚焦点偏一点，结束后回正
func _update_camera_focus(delta: float) -> void:
	var cam: Camera2D = get_node_or_null("Camera")
	if cam == null:
		return
	var weight := 1.0 - exp(-delta * 8.0)
	if cam_focus_left > 0.0:
		cam_focus_left = maxf(0.0, cam_focus_left - delta)
		if is_instance_valid(cam_focus_target):
			cam_focus_pos = cam_focus_target.global_position
		_cam_focus_center = _cam_focus_center.lerp(cam_focus_pos, weight)
		cam.global_position = _cam_focus_center
	else:
		cam.position = cam.position.lerp(Vector2.ZERO, weight)
	if cam_focus_left <= 0.0 and cam.position.length() < 0.1:
		cam.position = Vector2.ZERO

func _reset_camera_focus() -> void:
	cam_focus_target = null
	cam_focus_left = 0.0
	var cam: Camera2D = get_node_or_null("Camera")
	if cam != null:
		cam.position = Vector2.ZERO

# ---------------- 天赋（本局保留，随新场景重置） ----------------
func add_talent_points(amount: int) -> void:
	if amount <= 0:
		return
	talent_points += amount
	talents_changed.emit()

func spend_talent(attribute: String) -> bool:
	if talent_points <= 0 or is_dead():
		return false
	match attribute:
		"health":
			talent_health += 1
			hp_max = _base_hp_max + talent_health * 2.0
		"attack":
			talent_attack += 1
		"defense":
			talent_defense += 1
		_:
			return false
	talent_points -= 1
	talents_changed.emit()
	return true

func talent_attack_bonus() -> int:
	return floori(talent_attack / 5.0)

func talent_damage_reduction() -> int:
	return floori(talent_defense / 5.0)

func damage_after_defense(amount: float) -> float:
	return maxf(0.0, amount - talent_damage_reduction())

func get_talent_stats() -> Dictionary:
	return {"points": talent_points, "health": talent_health, "attack": talent_attack,
		"defense": talent_defense, "hp_max": hp_max, "regen": talent_health / 2.0,
		"attack_bonus": talent_attack_bonus(), "damage_reduction": talent_damage_reduction()}

func _update_talent_regen(delta: float) -> void:
	if is_dead() or talent_health <= 0:
		_health_regen_elapsed = 0.0
		return
	_health_regen_elapsed += maxf(0.0, delta)
	while _health_regen_elapsed >= 10.0:
		_health_regen_elapsed -= 10.0
		heal(talent_health / 2.0)

func unlock_claw() -> void:
	if has_claw:
		return
	has_claw = true
	claw_cooldown_left = 0.0
	claw_unlocked.emit()
