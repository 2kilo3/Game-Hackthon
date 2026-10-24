extends Node2D
## 未来时空的出场演出：现代形态走出，再完整播放变身；没有战斗接口或碰撞。

signal finished

const MODERN_FRAMES = preload("res://resources/boss_modern_frames.tres")
const TRANSFORM_FRAMES = preload("res://resources/transform_frames.tres")
const DIRS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

var entrance_walk_seconds := 1.3
var walk_speed := 70.0
var phase := "enter"
var entrance_left := 1.3
var sprite: AnimatedSprite2D

func _ready() -> void:
	entrance_left = entrance_walk_seconds
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = MODERN_FRAMES
	sprite.offset = Vector2(0, -48)
	add_child(sprite)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_align_transform)
	sprite.play("walk_S")
	modulate.a = 0.0

func _physics_process(delta: float) -> void:
	if phase != "enter":
		return
	entrance_left = maxf(0.0, entrance_left - delta)
	modulate.a = clampf(1.0 - entrance_left / entrance_walk_seconds, 0.0, 1.0)
	var player: Node2D = get_parent().get_node_or_null("Player")
	if player != null:
		var direction := (player.global_position - global_position).normalized()
		position += direction * walk_speed * 0.8 * delta
		var index := int(round(fposmod(rad_to_deg(direction.angle()), 360.0) / 45.0)) % 8
		sprite.play("walk_" + DIRS[index])
	if entrance_left <= 0.0:
		phase = "transform"
		modulate.a = 1.0
		sprite.sprite_frames = TRANSFORM_FRAMES
		sprite.play("transform")
		_align_transform()

func _align_transform() -> void:
	if phase != "transform" or sprite.animation != &"transform":
		return
	var progress := float(sprite.frame) / (TRANSFORM_FRAMES.get_frame_count("transform") - 1)
	var texture := TRANSFORM_FRAMES.get_frame_texture("transform", sprite.frame)
	var bounds := texture.get_image().get_used_rect()
	# 64px 变身图逐步长到 160px 动画中人物的可见尺寸，脚底衔接原立绘基线。
	var zoom := lerpf(1.0, 1.4, progress)
	sprite.scale = Vector2.ONE * zoom
	sprite.offset = Vector2(0, lerpf(-8.0, 5.0, progress) / zoom - (bounds.end.y - texture.get_height() / 2.0))

func remaining_seconds() -> float:
	var count := TRANSFORM_FRAMES.get_frame_count("transform")
	var duration := count / TRANSFORM_FRAMES.get_animation_speed("transform")
	return entrance_left + duration if phase == "enter" else (count - sprite.frame) / TRANSFORM_FRAMES.get_animation_speed("transform")

func _on_animation_finished() -> void:
	if phase == "transform":
		phase = "finished"
		finished.emit()
