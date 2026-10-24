extends StaticBody2D
## 现代时空的花盆：受到攻击就打碎（播 break 动画），并通知世界记录"这个花盆已碎"。
## 碎掉之后：碰撞彻底移除、动画播完隐藏（并释放节点），切时空再回来也保持已碎状态。

## 第几个花盆（0 / 1 / 2），和未来时空的能量桩一一对应
@export var pot_index := 0

@onready var sprite: AnimatedSprite2D = $Sprite

var broken := false

func _ready() -> void:
	sprite.play("break")
	sprite.pause()
	sprite.frame = 0
	sprite.animation_finished.connect(_on_break_finished)
	if _is_broken_in_world():
		_apply_broken(true)

func take_damage(_amount: float) -> void:
	if broken:
		return
	_apply_broken(false)

## 被打碎：清碰撞、播 break（播完隐藏 + 释放节点）、通知世界
func _apply_broken(silent: bool) -> void:
	broken = true
	_clear_collision()
	var w := _world()
	if w != null and w.has_method("mark_pot_broken"):
		w.mark_pot_broken(pot_index)
	if silent:
		visible = false
		return
	visible = true
	sprite.visible = true
	sprite.play("break")
	sprite.set_frame_and_progress(0, 0.0)

## 碰撞彻底清掉：
## 1) 形状用 set_deferred 关掉（物理回调里直接改会报 "flushing queries" 而无效）
## 2) 整个 body 退出碰撞层
## 3) 节点本身在动画播完后 queue_free，双保险
func _clear_collision() -> void:
	var col: CollisionShape2D = get_node_or_null("Collision")
	if col != null:
		col.set_deferred("disabled", true)
		col.queue_free()
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)

func _on_break_finished() -> void:
	if broken:
		visible = false

func _is_broken_in_world() -> bool:
	var w := _world()
	if w != null and w.has_method("is_pot_broken"):
		return bool(w.is_pot_broken(pot_index))
	return false

func _world() -> Node:
	var p := get_parent()
	if p != null:
		return p.get_parent()
	return null
