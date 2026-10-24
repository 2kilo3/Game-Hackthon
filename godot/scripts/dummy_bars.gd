extends Node2D
## 测试桩头顶的生命 / 韧性条。
## 单独一个节点并抬高 z_index，保证不会被角色或桩体挡住。

@export var bar_width := 52.0
@export var hp_height := 5.0
@export var poise_height := 3.0
@export var gap := 2.0
@export var offset_y := -62.0
@export var hp_color := Color(0.85, 0.33, 0.31, 1.0)
@export var poise_color := Color(0.88, 0.70, 0.30, 1.0)
@export var back_color := Color(0.20, 0.21, 0.24, 0.75)
@export var border_color := Color(0.10, 0.10, 0.12, 0.9)

var _dummy: Node

func _ready() -> void:
	z_index = 100
	_dummy = get_parent()

func _draw() -> void:
	if _dummy == null:
		return
	var hp_max: float = _dummy.hp_max
	var hp: float = clampf(_dummy.hp, 0.0, hp_max)
	var poise_max: float = _dummy.poise_max
	var poise: float = clampf(_dummy.poise, 0.0, poise_max)

	var x := -bar_width * 0.5
	var y := offset_y

	# 生命
	_draw_bar(Rect2(x, y, bar_width, hp_height), hp / hp_max if hp_max > 0.0 else 0.0, hp_color)
	# 韧性
	_draw_bar(Rect2(x, y + hp_height + gap, bar_width, poise_height),
		poise / poise_max if poise_max > 0.0 else 0.0, poise_color)

func _draw_bar(rect: Rect2, ratio: float, fill: Color) -> void:
	draw_rect(rect, back_color, true)
	if ratio > 0.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0.0, 1.0), rect.size.y)), fill, true)
	draw_rect(rect, border_color, false, 1.0)
