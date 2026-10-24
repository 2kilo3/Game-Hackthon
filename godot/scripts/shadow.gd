extends Node2D
## 落地阴影：随速度收扁、变淡的椭圆（纯代码绘制，不需要贴图）。
## 挂在 Player 下，位置就是脚底。

## 0 = 静止，1 = 全速跑（由 player.gd 每帧写入）
var speed_ratio := 0.0

const BASE_RX := 9.0
const BASE_RY := 3.6
const OFFSET_Y := -1.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var squash := 1.0 - 0.18 * speed_ratio
	var rx := BASE_RX * (1.0 + 0.06 * speed_ratio)
	var ry := maxf(1.5, BASE_RY * squash)
	var alpha := 0.20 * (1.0 - 0.35 * speed_ratio)
	# 用非等比缩放把圆压成椭圆，避免手写椭圆采样
	draw_set_transform(Vector2(0.0, OFFSET_Y), 0.0, Vector2(rx, ry))
	draw_circle(Vector2.ZERO, 1.0, Color(0.09, 0.11, 0.15, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
