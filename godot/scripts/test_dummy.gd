extends StaticBody2D
## 测试桩（原伤害墙改造）：可被攻击的目标，并周期性蓄力 → 放出一圈红色震荡波。
##
## 循环：静止 attack_interval 秒（其中最后 charge_time 秒在蓄力并变亮示警）→ 发出震荡波
##       震荡波在 wave_duration 内从 0 扩到 wave_max_radius，扫到玩家造成 wave_damage 伤害 + 轻微击退。
##
## 桩自身有生命 100 / 韧性 50（调试键 F7 可以打它）；血量归零后停止攻击，10 秒后自动满血复活。

@export_group("生命")
@export var hp_max := 100.0
@export var poise_max := 50.0
## 被打倒后多久自动复活（秒）
@export var revive_seconds := 10.0
## 韧性被打破后的瘫痪时长（秒）；期间不攻击，结束后韧性回满
@export var poise_break_seconds := 5.0

@export_group("攻击：震荡波")
## 每隔多少秒蓄力一次（从上一发结束算）
@export var attack_interval := 5.0
## 蓄力时长（秒），期间桩会变亮示警
@export var charge_time := 1.0
## 震荡波从 0 扩到最大半径的用时
@export var wave_duration := 0.4
@export var wave_max_radius := 140.0
@export var wave_damage := 10.0
## 命中后的击退速度
@export var wave_knockback := 220.0
@export var wave_color := Color(0.88, 0.24, 0.20, 1.0)

@export_group("外观")
@export var wall_size := Vector2(24, 96)
@export var base_color := Color(0.72, 0.26, 0.25, 1.0)
@export var stripe_color := Color(0.86, 0.42, 0.34, 1.0)
## 蓄力时表面偏向这个颜色（示警）
@export var charge_color := Color(1.0, 0.78, 0.45, 1.0)
@export var broken_color := Color(0.35, 0.32, 0.34, 1.0)

@onready var bars: Node2D = $Bars

var hp := 100.0
var poise := 50.0

var _cycle := 0.0          # 距离上一次开火的计时
var charging := false
var _charge_glow := 0.0    # 0..1，蓄力亮度
var wave_active := false
var _wave_t := 0.0
var _wave_hit := false
var revive_left := 0.0     # 被打倒后距离复活的秒数
var paralyzed_left := 0.0  # 韧性破裂后的瘫痪剩余秒数

func _ready() -> void:
	hp = hp_max
	poise = poise_max
	var shape := RectangleShape2D.new()
	shape.size = wall_size
	var col := get_node_or_null("Collision")
	if col != null:
		col.shape = shape
	else:
		var body_shape := CollisionShape2D.new()
		body_shape.name = "Collision"
		body_shape.shape = shape
		add_child(body_shape)
	# 从静止开始，第一次蓄力在 attack_interval - charge_time 秒后
	_cycle = 0.0

func _physics_process(delta: float) -> void:
	if is_broken():
		charging = false
		wave_active = false
		_charge_glow = 0.0
		revive_left = maxf(0.0, revive_left - delta)
		if revive_left <= 0.0:
			_revive()
		queue_redraw()
		if bars != null:
			bars.queue_redraw()
		return

	# 韧性破裂：瘫痪期间不攻击，结束后韧性回满、攻击循环从头开始
	if paralyzed_left > 0.0:
		paralyzed_left = maxf(0.0, paralyzed_left - delta)
		charging = false
		wave_active = false
		_charge_glow = 0.0
		if paralyzed_left <= 0.0:
			poise = poise_max
			_cycle = 0.0
		queue_redraw()
		if bars != null:
			bars.queue_redraw()
		return

	_update_cycle(delta)
	_update_wave(delta)
	queue_redraw()
	if bars != null:
		bars.queue_redraw()

## 复活：血量/韧性回满，攻击循环从头开始
func _revive() -> void:
	hp = hp_max
	poise = poise_max
	revive_left = 0.0
	_cycle = 0.0
	charging = false
	wave_active = false
	_flash()
	queue_redraw()

# ---------------- 攻击循环 ----------------
func _update_cycle(delta: float) -> void:
	_cycle += delta
	var charge_start := maxf(0.0, attack_interval - charge_time)
	if _cycle >= charge_start:
		charging = true
		# 蓄力亮度：随时间升高并轻微脉动
		var k := clampf((_cycle - charge_start) / maxf(0.001, charge_time), 0.0, 1.0)
		_charge_glow = k * (0.75 + 0.25 * sin(_cycle * 40.0))
	else:
		charging = false
		_charge_glow = 0.0

	if _cycle >= attack_interval:
		_cycle = 0.0
		_fire()

func _fire() -> void:
	charging = false
	_charge_glow = 0.0
	wave_active = true
	_wave_t = 0.0
	_wave_hit = false

func _update_wave(delta: float) -> void:
	if not wave_active:
		return
	_wave_t += delta
	var k := clampf(_wave_t / wave_duration, 0.0, 1.0)
	var radius := wave_max_radius * k

	# 冲击波扫过玩家时命中一次
	if not _wave_hit:
		var player := _find_player()
		if player != null:
			var dist: float = player.global_position.distance_to(global_position)
			if dist <= radius:
				_wave_hit = true
				var dir: Vector2 = player.global_position - global_position
				if player.has_method("try_take_hit"):
					# 返回 "hit" / "perfect" / "blocked" / "immune"
					var result: String = player.try_take_hit(wave_damage, global_position)
					if result == "hit" and player.has_method("apply_knockback"):
						player.apply_knockback(dir, wave_knockback)
				elif player.has_method("take_damage"):
					if player.take_damage(wave_damage) and player.has_method("apply_knockback"):
						player.apply_knockback(dir, wave_knockback)

	if _wave_t >= wave_duration:
		wave_active = false

func _find_player() -> Node2D:
	var n := get_parent().get_node_or_null("Player")
	if n is Node2D:
		return n
	return null

# ---------------- 受击（给之后的玩家攻击用，也供 F7 调试） ----------------
func take_damage(amount: float) -> void:
	var was_alive := not is_broken()
	hp = maxf(0.0, hp - maxf(0.0, amount))
	if was_alive and is_broken():
		# 刚被打倒：开始复活倒计时
		revive_left = revive_seconds
		charging = false
		wave_active = false
		_charge_glow = 0.0
	_flash()
	queue_redraw()

func damage_poise(amount: float) -> void:
	poise = clampf(poise - maxf(0.0, amount), 0.0, poise_max)
	if poise <= 0.0 and paralyzed_left <= 0.0 and not is_broken():
		paralyzed_left = poise_break_seconds
		charging = false
		wave_active = false
		_charge_glow = 0.0

## 是否处于韧性破裂的瘫痪状态
func is_paralyzed() -> bool:
	return paralyzed_left > 0.0
	queue_redraw()

func restore_poise(amount: float) -> void:
	poise = clampf(poise + maxf(0.0, amount), 0.0, poise_max)
	queue_redraw()

func is_broken() -> bool:
	return hp <= 0.0

func _flash() -> void:
	var tween := create_tween()
	modulate = Color(1.8, 1.8, 1.8, 1.0)
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)

# ---------------- 绘制 ----------------
func _draw() -> void:
	var rect := Rect2(-wall_size * 0.5, wall_size)
	var body := base_color
	if is_broken():
		body = broken_color
	elif charging:
		body = base_color.lerp(charge_color, _charge_glow)

	draw_rect(rect, body, true)
	var stripe := stripe_color if not is_broken() else broken_color.lightened(0.12)
	if charging:
		stripe = stripe.lerp(charge_color, _charge_glow)
	var y := rect.position.y + 5.0
	while y + 4.0 < rect.end.y:
		draw_rect(Rect2(rect.position.x, y, wall_size.x, 4.0), stripe, true)
		y += 10.0
	draw_rect(rect, Color(0.45, 0.16, 0.16, 1.0), false, 1.0)

	# 被打倒时在头顶画一条复活进度
	if is_broken() and revive_seconds > 0.0:
		var progress := clampf(1.0 - revive_left / revive_seconds, 0.0, 1.0)
		var bar_w := wall_size.x
		var bar_y := wall_size.y * 0.5 + 4.0   # 画在桩脚下，避免和头顶的血条重叠
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, 3.0), Color(0.1, 0.1, 0.12, 0.45), true)
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * progress, 3.0), Color(0.62, 0.82, 1.0, 0.95), true)

	# 蓄力时脚下画一个收拢的警示圈，强化"要打了"的预告
	if charging:
		var warn := 18.0 + 10.0 * (0.5 + 0.5 * sin(_cycle * 30.0))
		draw_arc(Vector2.ZERO, warn, 0.0, TAU, 32, Color(charge_color.r, charge_color.g, charge_color.b, 0.55), 2.0)

	# 震荡波
	if wave_active:
		var k := clampf(_wave_t / wave_duration, 0.0, 1.0)
		var radius := wave_max_radius * k
		var alpha := (1.0 - k) * 0.9
		var col := Color(wave_color.r, wave_color.g, wave_color.b, alpha)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, col, 3.0)
		draw_arc(Vector2.ZERO, radius * 0.82, 0.0, TAU, 48, Color(wave_color.r, wave_color.g, wave_color.b, alpha * 0.5), 2.0)
