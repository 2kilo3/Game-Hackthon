extends StaticBody2D
## 第二个测试桩：周围有人时，每 10 秒打出一轮 5 发子弹（每发 2 点伤害）。
##
## - 玩家进入 detect_radius 才计时；离开范围会清零，不会远程偷袭
## - 一轮 5 发，按 volley_gap 间隔连续射出，子弹朝开火瞬间的玩家位置飞
## - 也能被玩家普攻打，血量归零停止射击，10 秒后自动复活（和第一个桩一致）

@export_group("生命")
@export var hp_max := 80.0
@export var poise_max := 50.0
## 被打倒后多久自动复活（秒）
@export var revive_seconds := 10.0
## 韧性被打破后的瘫痪时长（秒）；期间不开枪，结束后韧性回满
@export var poise_break_seconds := 5.0

@export_group("射击")
## 玩家进入这个半径才会开枪
@export var detect_radius := 260.0
## 每轮之间的间隔（秒）
@export var volley_interval := 10.0
## 一轮几发
@export var volley_count := 5
## 连发之间的间隔（秒）
@export var volley_gap := 0.12
## 每发伤害
@export var bullet_damage := 2.0
@export var bullet_speed := 170.0
@export var bullet_max_distance := 340.0

@export_group("外观")
@export var body_size := Vector2(24, 76)
@export var base_color := Color(0.24, 0.40, 0.58, 1.0)
@export var core_color := Color(0.45, 0.85, 1.0, 1.0)
@export var broken_color := Color(0.32, 0.33, 0.36, 1.0)

@onready var bars: Node2D = $Bars

const BULLET_SCENE := preload("res://scenes/bullet.tscn")

var hp := 80.0
var poise := 50.0
var revive_left := 0.0
var paralyzed_left := 0.0  # 韧性破裂后的瘫痪剩余秒数
## 已经打出的子弹数（调试 / 测试用）
var bullets_fired := 0

var _timer := 0.0          # 距离下一轮
var _pending := 0          # 本轮还剩几发
var _next_shot := 0.0
var _glow := 0.0

func _ready() -> void:
	hp = hp_max
	poise = poise_max
	var shape := RectangleShape2D.new()
	shape.size = body_size
	var col := get_node_or_null("Collision")
	if col != null:
		col.shape = shape
	else:
		var body_shape := CollisionShape2D.new()
		body_shape.name = "Collision"
		body_shape.shape = shape
		add_child(body_shape)

func _physics_process(delta: float) -> void:
	if is_broken():
		_pending = 0
		_glow = 0.0
		revive_left = maxf(0.0, revive_left - delta)
		if revive_left <= 0.0:
			_revive()
		queue_redraw()
		if bars != null:
			bars.queue_redraw()
		return

	if paralyzed_left > 0.0:
		paralyzed_left = maxf(0.0, paralyzed_left - delta)
		_pending = 0
		_glow = 0.0
		if paralyzed_left <= 0.0:
			poise = poise_max
			_timer = 0.0
		queue_redraw()
		if bars != null:
			bars.queue_redraw()
		return

	var player := _find_player()
	var in_range := player != null and global_position.distance_to(player.global_position) <= detect_radius

	if in_range:
		_timer += delta
		if _timer >= volley_interval:
			_timer = 0.0
			_start_volley(player)
	else:
		_timer = 0.0
		_pending = 0

	# 连发
	if _pending > 0:
		_next_shot -= delta
		if _next_shot <= 0.0:
			_fire(player)
			_pending -= 1
			_next_shot = volley_gap

	_glow = maxf(0.0, _glow - delta * 3.0)
	queue_redraw()
	if bars != null:
		bars.queue_redraw()

func _start_volley(player: Node2D) -> void:
	_fire(player)
	_pending = maxi(0, volley_count - 1)
	_next_shot = volley_gap
	_glow = 1.0

func _fire(player: Node2D) -> void:
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

func _find_player() -> Node2D:
	var n := get_parent().get_node_or_null("Player")
	if n is Node2D:
		return n
	return null

# ---------------- 受击 / 复活 ----------------
func take_damage(amount: float) -> void:
	var was_alive := not is_broken()
	hp = maxf(0.0, hp - maxf(0.0, amount))
	if was_alive and is_broken():
		revive_left = revive_seconds
		_pending = 0
		_glow = 0.0
	queue_redraw()

func damage_poise(amount: float) -> void:
	poise = clampf(poise - maxf(0.0, amount), 0.0, poise_max)
	if poise <= 0.0 and paralyzed_left <= 0.0 and not is_broken():
		paralyzed_left = poise_break_seconds
		_pending = 0
		_glow = 0.0

## 是否处于韧性破裂的瘫痪状态
func is_paralyzed() -> bool:
	return paralyzed_left > 0.0
	queue_redraw()

func is_broken() -> bool:
	return hp <= 0.0

func _revive() -> void:
	hp = hp_max
	poise = poise_max
	revive_left = 0.0
	_timer = 0.0
	queue_redraw()

# ---------------- 绘制 ----------------
func _draw() -> void:
	var rect := Rect2(-body_size * 0.5, body_size)
	var body := broken_color if is_broken() else base_color
	draw_rect(rect, body, true)
	draw_rect(rect, body.darkened(0.35), false, 1.0)

	if not is_broken():
		# 枪口核心：开火时亮一下
		var core := core_color.lerp(Color.WHITE, _glow)
		var r := 5.0 + 2.0 * _glow
		draw_circle(Vector2(0, -body_size.y * 0.22), r, core)
		draw_circle(Vector2(0, -body_size.y * 0.22), r * 0.45, Color(1, 1, 1, 0.9))
	# 复活进度条（脚下）
	if is_broken() and revive_seconds > 0.0:
		var progress := clampf(1.0 - revive_left / revive_seconds, 0.0, 1.0)
		var bar_w := body_size.x
		var bar_y := body_size.y * 0.5 + 4.0
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, 3.0), Color(0.1, 0.1, 0.12, 0.45), true)
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * progress, 3.0), Color(0.62, 0.82, 1.0, 0.95), true)
