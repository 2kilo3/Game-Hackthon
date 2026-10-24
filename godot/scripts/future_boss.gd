extends CharacterBody2D
## 未来 boss：持盾冲锋者
##
## - 生命 200 / 护盾 50 / 韧性 50，护盾每次最多扣 10 点
## - 初始持盾：走路、射击都是持盾动作；受击触发持盾格挡（不削韧性）
## - 每 3 秒选一次：五连射 或 持盾冲锋（冲锋不格挡、减伤 50%、命中 15 点，
##   普通格挡挡不住，完美格挡/完美闪避可以）
## - 护盾被打空：立刻破防一次；恢复后 60 秒不举盾（普通射击、可被削韧性），
##   60 秒后恢复 20 点护盾并重新举盾
## - 入场：现代 boss 被击败且小怪全清后，由世界完成现代形态出场与变身，再持盾冲锋进场

signal defeated_charge   # 冲锋开始时（测试/音效用）
signal died
signal player_killed

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
## 屏幕坐标：0° = 右(E)，顺时针。索引必须和 0°=E 对齐，否则朝向会错 90°
const DIRS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

@export var hp_max := 150.0
@export var shield_max := 100.0
@export var poise_max := 50.0
## 护盾单次最多掉多少
@export var shield_damage_cap := 10.0
## 普通攻击每下削减的韧性
@export var hit_poise_damage := 2.0
## 五连射
@export var volley_count := 5
@export var volley_gap := 0.16
@export var bullet_damage := 3.0
@export var bullet_speed := 360.0
## 冲锋
@export var charge_speed := 195.0
@export var charge_duration := 0.8
@export var charge_damage := 15.0
@export var charge_hit_radius := 34.0
## 决策间隔
@export var decision_interval := 3.0
## 护盾恢复
@export var shield_recover_delay := 60.0
@export var shield_recover_amount := 20.0
## 破防时长
@export var break_seconds := 4.0
## 尸体保留
@export var corpse_seconds := 20.0
@export var move_speed := 90.0
@export var walk_speed := 62.0
@export var detect_radius := 900.0
@export var keep_distance := 190.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var bars: Node2D = $Bars
@onready var shoot_sfx: AudioStreamPlayer = $ShootSfx
@onready var block_sfx: AudioStreamPlayer = $BlockSfx
@onready var charge_sfx: AudioStreamPlayer = $ChargeSfx
@onready var bash_sfx: AudioStreamPlayer = $BashSfx

var hp := 150.0
var shield := 100.0
var poise := 50.0
## 是否举盾（破盾后 60 秒内为 false）
var shield_up := true
var dead := false
var dead_left := 0.0
## 状态：enter / walk / shoot / normal_shoot / charge / bash / block / paralyzed
var state := "enter"
var facing := "S"

var _decision_left := 3.0
var _charge_left := 0.0
var _charge_dir := Vector2.DOWN
var _charge_hit_done := false
var _paralyzed_left := 0.0
var _no_shield_left := 0.0
var _block_left := 0.0
var _shoot_timer := 0.0
var _shots_left := 0
var _shot_gap := 0.0
var _entered := false
## 调试/测试用
var volleys_fired := 0
## 被眩晕剩余时间（钩爪）
var stun_left := 0.0
var charges_made := 0
var shield_breaks := 0

## 由世界在"小怪清完 + 主角在未来"时调用：从场边持盾冲锋入场
func begin_entrance() -> void:
	var world := get_parent().get_parent()
	if world != null and world.has_method("_set_era_entities") and not Timeline.is_future():
		return
	if _entered or dead:
		return
	_entered = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(true)
	# 入场强制复位成"活着且满状态"（防止之前被清成 0 血/死亡姿态）
	dead = false
	dead_left = 0.0
	hp = hp_max
	shield = shield_max
	poise = poise_max
	shield_up = true
	_paralyzed_left = 0.0
	_no_shield_left = 0.0
	_block_left = 0.0
	_shots_left = 0
	_charge_hit_done = false
	modulate = Color(1, 1, 1, 1)
	state = "enter"
	_charge_left = 1.1
	_decision_left = decision_interval
	velocity = Vector2.ZERO
	var col: CollisionShape2D = get_node_or_null("Collision")
	if col != null:
		col.set_deferred("disabled", false)
	if bars != null:
		bars.visible = true
	_facing_init()
	_play("charge")
	_play_sfx(charge_sfx, -12.0)

func _ready() -> void:
	add_to_group("future_boss")
	add_to_group("boss")
	hp = hp_max
	shield = shield_max
	poise = poise_max
	velocity = Vector2.ZERO
	_play("shield_walk")
	if bars != null:
		bars.queue_redraw()

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		dead_left = maxf(0.0, dead_left - delta)
		if dead_left <= 0.0:
			queue_free()
		return

	if stun_left > 0.0:
		stun_left = maxf(0.0, stun_left - delta)
		if _paralyzed_left > 0.0:
			velocity = Vector2.ZERO
		else:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			move_and_slide()
		_refresh_bars()
		return

	var player := _find_player()

	# 入场：一路持盾冲锋
	if state == "enter":
		_entered = true
		var to_player: Vector2 = (player.global_position - global_position) if player != null else Vector2.DOWN
		_face(to_player)
		_play("charge")
		velocity = to_player.normalized() * charge_speed * 0.8 if to_player.length() > 1.0 else Vector2.ZERO
		move_and_slide()
		_charge_left -= delta
		if _charge_left <= 0.0:
			state = "walk"
		return

	# 破防（瘫痪）：动画只播一次，之后保持倒地姿势（不循环）
	if _paralyzed_left > 0.0:
		_paralyzed_left = maxf(0.0, _paralyzed_left - delta)
		# 零速度的 move_and_slide 也会解算重叠，把倒地 Boss 推离原位。
		velocity = Vector2.ZERO
		if _paralyzed_left <= 0.0:
			poise = poise_max
			state = "walk"
		_refresh_bars()
		return

	_shoot_timer = maxf(0.0, _shoot_timer - delta)
	# 破盾后的 60 秒：不举盾，只普通射击
	if not shield_up:
		_no_shield_left = maxf(0.0, _no_shield_left - delta)
		if _no_shield_left <= 0.0:
			shield_up = true
			shield = shield_recover_amount
			_decision_left = decision_interval

	# 普通射击完整播完才允许移动，期间恢复护盾也不截断动画。
	if state == "normal_shoot":
		velocity = Vector2.ZERO
		if sprite.is_playing():
			_refresh_bars()
			return
		state = "walk"

	if not shield_up:
		if not _try_normal_shot(player):
			_update_walk(delta, player, false)
		_refresh_bars()
		return

	# 持盾状态
	if state == "charge":
		_update_charge(delta, player)
		_refresh_bars()
		return
	if _block_left > 0.0:
		_block_left = maxf(0.0, _block_left - delta)
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		if _block_left <= 0.0:
			state = "walk"
		_refresh_bars()
		return
	if _shots_left > 0:
		_update_volley(delta, player)
		_refresh_bars()
		return

	_update_walk(delta, player, true)
	_decision_left -= delta
	if _decision_left <= 0.0:
		_decision_left = decision_interval
		if randf() < 0.35:
			_start_volley(player)
		else:
			_start_charge(player)
	_refresh_bars()

# ---------------- 行动 ----------------
func _update_walk(delta: float, player: Node2D, shield_form: bool) -> void:
	var desired := Vector2.ZERO
	if player != null:
		var to_player: Vector2 = player.global_position - global_position
		if to_player.length() > keep_distance:
			desired = to_player.normalized() * walk_speed
		elif to_player.length() < keep_distance - 40.0:
			desired = -to_player.normalized() * walk_speed * 0.7
		elif to_player.length() > 1.0:
			desired = to_player.normalized().orthogonal() * walk_speed * 0.5
		if to_player.length() > 1.0:
			_face(to_player)
	velocity = velocity.move_toward(desired, 420.0 * delta)
	move_and_slide()
	if state != "walk" and state != "enter":
		state = "walk"
	_play("shield_walk" if shield_form else "walk")

## 持盾时：五连射
func _start_volley(player: Node2D) -> void:
	_shots_left = volley_count
	_shot_gap = 0.0
	state = "shoot"
	velocity = Vector2.ZERO
	if player != null:
		_face(player.global_position - global_position)
	_play("shield_shoot" if shield_up else "shoot", false)

func _update_volley(delta: float, player: Node2D) -> void:
	# 攻击时站定不动，动画在 _start_volley 里只播一次（不能每帧重播）
	velocity = Vector2.ZERO
	move_and_slide()
	_shot_gap -= delta
	if _shot_gap <= 0.0 and _shots_left > 0:
		_shots_left -= 1
		_shot_gap = volley_gap
		_fire(player)
	if _shots_left <= 0:
		state = "walk"

## 不举盾时：普通射击（更慢、单发）
func _try_normal_shot(player: Node2D) -> bool:
	if _shoot_timer > 0.0 or player == null:
		return false
	_shoot_timer = 1.4
	velocity = Vector2.ZERO
	_face(player.global_position - global_position)
	_play("shoot", false)
	_fire(player)
	state = "normal_shoot"
	return true

func _fire(player: Node2D) -> void:
	if player == null:
		return
	var layer := get_parent()
	if layer == null:
		return
	var bullet: Node2D = BULLET_SCENE.instantiate()
	bullet.direction = (player.global_position - global_position).normalized()
	bullet.speed = bullet_speed
	bullet.damage = bullet_damage
	bullet.max_distance = 900.0
	bullet.source_pos = global_position
	bullet.position = global_position
	bullet.player_killed.connect(func(): player_killed.emit())
	layer.add_child(bullet)
	volleys_fired += 1
	_play_sfx(shoot_sfx, -14.0)

## 持盾冲锋
func _start_charge(player: Node2D) -> void:
	if player == null:
		return
	charges_made += 1
	_face(player.global_position - global_position)
	# 冲锋方向和面朝方向保持一致（用 facing 反算方向向量）
	_charge_dir = _dir_vector(facing)
	state = "charge"
	_charge_left = charge_duration
	_charge_hit_done = false
	_play("charge")
	_play_sfx(charge_sfx, -12.0)
	defeated_charge.emit()

func _update_charge(delta: float, player: Node2D) -> void:
	_charge_left -= delta
	velocity = _charge_dir * charge_speed
	move_and_slide()
	if player != null and not _charge_hit_done:
		if global_position.distance_to(player.global_position) <= charge_hit_radius:
			_charge_hit_done = true
			state = "bash"
			_play("bash", false)
			_play_sfx(bash_sfx, -9.0)
			if player.has_method("try_take_hit"):
				var was_alive: bool = player.has_method("is_dead") and not player.is_dead()
				# 冲锋攻击：普通格挡挡不住（bypass_block），完美格挡/完美闪避仍然有效
				player.try_take_hit(charge_damage, global_position, true)
				if was_alive and player.is_dead():
					player_killed.emit()
			_charge_left = 0.35
			if charge_sfx != null:
				charge_sfx.stop()
	if _charge_left <= 0.0 and state == "charge":
		state = "walk"
		if charge_sfx != null:
			charge_sfx.stop()   # 冲锋结束就停，不完整播完

# ---------------- 受击 ----------------
## 玩家攻击调用：护盾在就格挡（护盾最多掉 10），破盾后才会掉血/掉韧性
func take_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return

	# 冲锋中：不格挡、减伤 50%
	if state == "charge" or state == "bash":
		hp = maxf(0.0, hp - amount * 0.5)
		_apply_hit_poise()
		if hp <= 0.0:
			_die()
		_refresh_bars()
		return

	# 有护盾：盾吸收伤害（单次最多 10），但**普攻照样削韧性**
	if shield_up and shield > 0.0:
		var shield_loss: float = minf(amount, shield_damage_cap)
		shield = maxf(0.0, shield - shield_loss)
		_apply_hit_poise()
		state = "block"
		_block_left = 0.28
		_play("block", false)
		_play_sfx(block_sfx, -10.0)
		if shield <= 0.0:
			_on_shield_broken()
		_refresh_bars()
		return

	# 没盾：正常掉血（韧性也会被普攻慢慢削）
	hp = maxf(0.0, hp - amount)
	_apply_hit_poise()
	if hp <= 0.0:
		_die()
	_refresh_bars()

## 普通攻击每次削 2 点韧性
func _apply_hit_poise() -> void:
	poise = maxf(0.0, poise - hit_poise_damage)
	if poise <= 0.0 and _paralyzed_left <= 0.0 and state != "charge" and state != "bash":
		_enter_paralyzed()

## 反击削韧性（只有玩家的反击会调这个）
func damage_poise(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	poise = maxf(0.0, poise - amount)
	if poise <= 0.0:
		_enter_paralyzed()
	_refresh_bars()

## 被钩爪拉过来的眩晕
func stun(seconds: float) -> void:
	if dead:
		return
	stun_left = maxf(stun_left, seconds)
	velocity = Vector2.ZERO
	if state == "normal_shoot":
		state = "walk"
	_play("paralyzed", false)

## 能量桩激光：只扣护盾/生命，**不削韧性**
func take_laser_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	if shield_up and shield > 0.0:
		shield = maxf(0.0, shield - amount)
		if shield <= 0.0:
			_on_shield_broken()
	elif state != "charge" and state != "bash":
		hp = maxf(0.0, hp - amount)
		if hp <= 0.0:
			_die()
	_refresh_bars()

## 护盾打空：立刻破防一次，之后 60 秒不举盾
func _on_shield_broken() -> void:
	shield_breaks += 1
	shield = 0.0
	shield_up = false
	_no_shield_left = shield_recover_delay
	_shoot_timer = 0.0
	_shots_left = 0
	_block_left = 0.0
	_enter_paralyzed()

func _enter_paralyzed() -> void:
	_paralyzed_left = break_seconds
	state = "paralyzed"
	velocity = Vector2.ZERO
	_play("paralyzed", false)

func _die() -> void:
	if dead:
		return
	dead = true
	dead_left = corpse_seconds
	state = "dead"
	velocity = Vector2.ZERO
	died.emit()
	_play("paralyzed", false)
	modulate = Color(0.55, 0.55, 0.6, 0.85)
	if bars != null:
		bars.visible = false
	var col: CollisionShape2D = get_node_or_null("Collision")
	if col != null:
		col.disabled = true

# ---------------- 工具 ----------------
## 入场时朝玩家方向
func _facing_init() -> void:
	var p := _find_player()
	if p != null:
		_face(p.global_position - global_position)

## 方向名 → 单位向量（和 DIRS 的 0°=E 对齐）
func _dir_vector(dir_name: String) -> Vector2:
	var idx := DIRS.find(dir_name)
	if idx < 0:
		idx = 0
	var deg: float = idx * 45.0
	return Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg)))

func _face(v: Vector2) -> void:
	if v.length() < 0.001:
		return
	var deg := rad_to_deg(v.angle())
	facing = DIRS[int(round(fposmod(deg, 360.0) / 45.0)) % 8]

func _play(anim: String, _loop: bool = true) -> void:
	var full := anim + "_" + facing
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(full):
		full = anim + "_S"
	if sprite.animation != full or not sprite.is_playing():
		sprite.play(full)

## 播放音效：base_db 为基础音量，离玩家越远越小声（最低 25%）
func _play_sfx(player: AudioStreamPlayer, base_db: float = -11.0) -> void:
	if player == null or player.stream == null:
		return
	var p := _find_player()
	var atten := 1.0
	if p != null:
		var dist := global_position.distance_to(p.global_position)
		atten = clampf(1.0 - dist / 760.0, 0.22, 1.0)
	player.volume_db = base_db + linear_to_db(atten)
	player.play()
	if player.get_meta("one_shot_stop", false) == false:
		pass

func _refresh_bars() -> void:
	if bars != null and bars.visible:
		bars.queue_redraw()
	queue_redraw()

func _draw() -> void:
	# 护盾条（画在血条上方，绿色）
	if dead:
		return
	var w := 52.0
	var y := -70.0
	draw_rect(Rect2(-w * 0.5, y, w, 3.0), Color(0.15, 0.3, 0.22, 0.85), true)
	var ratio: float = clampf(shield / maxf(shield_max, 1.0), 0.0, 1.0)
	if ratio > 0.0:
		draw_rect(Rect2(-w * 0.5, y, w * ratio, 3.0), Color(0.35, 0.9, 0.65, 1.0), true)

func _find_player() -> Node2D:
	var p := get_parent()
	if p != null:
		var n := p.get_node_or_null("Player")
		if n is Node2D:
			return n
	return null
