extends Node2D
signal player_killed
## 测试桩发射的子弹：直线飞行，碰到玩家就调用 player.try_take_hit()。
##
## 用简单的距离判定代替物理碰撞（子弹少、判定直接），
## 命中后立刻销毁；飞太远也销毁，避免残留。

@export var speed := 170.0
@export var damage := 2.0
@export var max_distance := 360.0
## 命中判定半径（子弹半径 + 一点余量）
@export var hit_radius := 10.0

var direction := Vector2.RIGHT
## 攻击来源（射击的桩的位置），格挡/闪避判定要用
var source_pos := Vector2.ZERO

var _traveled := 0.0

func _ready() -> void:
	add_to_group("era_projectile")

## 给玩家反击识别用
func is_bullet() -> bool:
	return true

func destroy_bullet() -> void:
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 4.0, Color(0.35, 0.78, 1.0, 0.95))
	draw_circle(Vector2.ZERO, 2.0, Color(1, 1, 1, 1))

func _physics_process(delta: float) -> void:
	var step: float = speed * delta
	position += direction * step
	_traveled += step

	var player := get_parent().get_node_or_null("Player")
	if player is Node2D:
		if global_position.distance_to(player.global_position) <= hit_radius:
			if player.has_method("try_take_hit"):
				var was_alive: bool = player.has_method("is_dead") and not player.is_dead()
				player.try_take_hit(damage, source_pos)
				if was_alive and player.is_dead():
					player_killed.emit()
			queue_free()
			return

	if _traveled >= max_distance:
		queue_free()
