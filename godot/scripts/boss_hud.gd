extends Node2D
## 固定在屏幕顶部中间的 boss 状态条（生命 / 护盾 / 韧性）。
## boss 入场后常驻显示，保证足够显眼。

@export var bar_width := 260.0
@export var top_y := 12.0

var _boss: Node = null

func _ready() -> void:
	z_index = 200

func _process(_delta: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		_boss = _find_boss()
	queue_redraw()

func _find_boss() -> Node:
	var root := get_tree().current_scene
	if root == null:
		return null
	return root.find_child("FutureBoss", true, false)

func _draw() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	if not bool(_boss.get("visible")):
		return
	if bool(_boss.get("dead")):
		return
	var vp := get_viewport_rect().size
	var x: float = (vp.x - bar_width) * 0.5
	var hp: float = float(_boss.get("hp"))
	var hp_max: float = maxf(1.0, float(_boss.get("hp_max")))
	var shield: float = float(_boss.get("shield"))
	var shield_max: float = maxf(1.0, float(_boss.get("shield_max")))
	var poise: float = float(_boss.get("poise"))
	var poise_max: float = maxf(1.0, float(_boss.get("poise_max")))

	# 标题
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, Vector2(x, top_y - 1.0), "未来守盾者",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.95))

	# 护盾（绿）
	_bar(Rect2(x, top_y + 1.0, bar_width, 5.0), shield / shield_max, Color(0.30, 0.85, 0.60, 1.0))
	# 生命（红）
	_bar(Rect2(x, top_y + 8.0, bar_width, 7.0), hp / hp_max, Color(0.85, 0.28, 0.26, 1.0))
	# 韧性（黄）
	_bar(Rect2(x, top_y + 17.0, bar_width, 4.0), poise / poise_max, Color(0.88, 0.72, 0.30, 1.0))

func _bar(rect: Rect2, ratio: float, fill: Color) -> void:
	draw_rect(rect, Color(0.08, 0.09, 0.11, 0.8), true)
	draw_rect(rect, Color(0.85, 0.87, 0.9, 0.55), false, 1.0)
	var r: float = clampf(ratio, 0.0, 1.0)
	if r > 0.0:
		draw_rect(Rect2(rect.position.x + 1.0, rect.position.y + 1.0, (rect.size.x - 2.0) * r, rect.size.y - 2.0), fill, true)
