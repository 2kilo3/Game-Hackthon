extends Node2D
## 闪避残影：每移动固定距离就复制一帧半透明幽灵，淡出后销毁。
##
## 关键细节（之前出现过"残影散在路径上/初始点"的问题）：
##   1. 位置在 add_child **之前**就设好，避免幽灵在 (0,0) 出生点闪一帧。
##   2. 按"移动距离"而不是时间生成：速度再快间距也均匀，不会拉成一串离散的复制人。
##   3. 起手时把记录点对齐当前位置，所以起点不会留下残影。
##   4. 极限闪避触发后（set_golden(true)），本次闪避后续残影改成金色。

## 每移动多少世界像素生成一个残影
@export var step_distance := 10.0
## 单个残影存活时间（秒）
@export var lifetime := 0.12
@export var start_alpha := 0.22
## 金色残影的透明度（比普通残影更明显，突出极限闪避）
@export var perfect_alpha := 0.6
@export var tint := Color(0.72, 0.86, 1.0, 1.0)
## 极限闪避后残影的颜色
@export var perfect_tint := Color(1.0, 0.65, 0.10, 1.0)
## 同时存在的残影上限
@export var max_ghosts := 10

var _sprite: AnimatedSprite2D
var _layer: Node
var _active := false
var _last_pos := Vector2.INF
var _alive := 0
var _golden := false

func setup(sprite: AnimatedSprite2D, layer: Node) -> void:
	_sprite = sprite
	_layer = layer

func set_active(active: bool) -> void:
	_active = active
	if active:
		# 以当前位置为起点：移动满 step_distance 才留第一个影
		_last_pos = _sprite.global_position if _sprite != null else Vector2.INF
	else:
		_golden = false

## 极限闪避触发后切金色；下一次闪避开始时由 set_active(true) 复位
func set_golden(golden: bool) -> void:
	_golden = golden

func is_golden() -> bool:
	return _golden

func _process(_delta: float) -> void:
	if not _active or _sprite == null or _layer == null:
		return
	var pos := _sprite.global_position
	if _last_pos == Vector2.INF:
		_last_pos = pos
		return
	if pos.distance_to(_last_pos) < step_distance:
		return
	_last_pos = pos
	_spawn(pos)

func _spawn(world_pos: Vector2) -> void:
	if _sprite.sprite_frames == null or _alive >= max_ghosts:
		return
	var tex := _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	if tex == null:
		return

	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.offset = _sprite.offset
	ghost.centered = _sprite.centered
	ghost.scale = _sprite.scale
	var col: Color = perfect_tint if _golden else tint
	var alpha: float = perfect_alpha if _golden else start_alpha
	ghost.modulate = Color(col.r, col.g, col.b, alpha)
	ghost.z_index = -1
	# 先设位置再加入场景树，避免在父节点原点闪一帧
	ghost.position = _layer.to_local(world_pos)
	_layer.add_child(ghost)
	_alive += 1

	var tween := create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, lifetime)
	tween.tween_callback(func() -> void:
		_alive = maxi(0, _alive - 1)
		ghost.queue_free()
	)
