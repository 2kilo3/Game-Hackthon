extends Node2D
## 玩家钩爪的实体：飞向目标 → 命中后把目标拉到玩家身边并眩晕 → 收回。
## 用 T11 钩爪素材（8 方向 throw / retract / rope）。

@export var fly_speed := 900.0
@export var stun_seconds := 1.0
@export var return_speed := 1100.0

const DIRS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

@onready var sprite: AnimatedSprite2D = $Sprite

## 目标敌人
var target: Node2D = null
## 发射者（玩家）
var owner_actor: Node2D = null

var phase := "out"   # out / back
var facing := "S"
var _hit := false

func _ready() -> void:
	add_to_group("era_projectile")
	z_index = 20
	if target != null:
		var v: Vector2 = target.global_position - global_position
		if v.length() > 0.001:
			_face(v)

func _physics_process(delta: float) -> void:
	if phase == "out":
		if not _target_active():
			phase = "back"
		else:
			var to_target: Vector2 = target.global_position - global_position
			if to_target.length() <= 16.0:
				_hit_target()
			else:
				global_position += to_target.normalized() * fly_speed * delta
				_play("throw")
	else:
		var home: Node2D = owner_actor
		if home == null or not is_instance_valid(home):
			queue_free()
			return
		var home_pos: Vector2 = home.global_position
		var back: Vector2 = home_pos - global_position
		if back.length() <= 18.0:
			queue_free()
			return
		global_position += back.normalized() * return_speed * delta
		_play("retract")
	queue_redraw()

## 命中：拉过来 + 眩晕
func _hit_target() -> void:
	if _hit:
		return
	_hit = true
	phase = "back"
	if _target_active():
		var home: Node2D = owner_actor
		if home != null and is_instance_valid(home):
			var dir: Vector2 = (target.global_position - home.global_position).normalized()
			target.global_position = home.global_position + dir * 34.0
		if target.has_method("stun"):
			target.stun(stun_seconds)

func _draw() -> void:
	var home: Node2D = owner_actor
	if home == null or not is_instance_valid(home):
		return
	# 绳子：从玩家手部到自己
	var from: Vector2 = home.global_position + Vector2(0, -20) - global_position
	draw_line(from, Vector2.ZERO, Color(0.85, 0.82, 0.7, 0.9), 2.0)
	draw_line(from, Vector2.ZERO, Color(0.35, 0.3, 0.25, 0.9), 1.0)

func _play(anim: String) -> void:
	var full := anim + "_" + facing
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(full):
		return
	if sprite.animation != full:
		sprite.play(full)

func _face(v: Vector2) -> void:
	if v.length() < 0.001:
		return
	var deg := rad_to_deg(v.angle())
	facing = DIRS[int(round(fposmod(deg, 360.0) / 45.0)) % 8]

func _target_active() -> bool:
	return is_instance_valid(target) and target.is_visible_in_tree() and target.process_mode != Node.PROCESS_MODE_DISABLED
