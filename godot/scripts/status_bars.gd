extends Control
## 状态条（占位 UI）：生命 / 韧性 / 体力。
##
## 全部用纯代码绘制，等有美术素材时把这个节点换掉即可，
## 外部接口只用 player.hp / hp_max / poise / poise_max / stamina / stamina_max。

@export var player_path: NodePath = ^"../../YSort/Player"

@export_group("生命")
@export var hp_pos := Vector2(8, 6)
@export var hp_size := Vector2(96, 7)
@export var hp_color := Color(0.85, 0.33, 0.31, 1.0)
@export var hp_low_color := Color(0.95, 0.62, 0.20, 1.0)

@export_group("韧性")
@export var poise_pos := Vector2(8, 17)
@export var poise_size := Vector2(96, 5)
@export var poise_color := Color(0.88, 0.70, 0.30, 1.0)
@export var poise_broken_color := Color(0.72, 0.45, 0.72, 1.0)
@export var exhaust_color := Color(0.55, 0.58, 0.66, 1.0)
@export var exhaust_label_color := Color(0.78, 0.22, 0.22, 1.0)

## 体力条位置；y 是相对视口底部的偏移（负数往上），这样换视口尺寸也不会跑位
@export var stamina_pos := Vector2(8, -21.0)
@export var stamina_size := Vector2(84, 7)
@export var stamina_color := Color(0.29, 0.64, 0.87, 1.0)
@export var stamina_low_color := Color(0.93, 0.53, 0.29, 1.0)

@export_group("外观")
@export var empty_color := Color(0.86, 0.88, 0.91, 1.0)
@export var border_color := Color(0.42, 0.45, 0.50, 1.0)
@export var label_color := Color(0.16, 0.18, 0.22, 1.0)
## 时空标签：右边显示「现代 / 未来」
@export var era_gap := 8.0
@export var era_modern_color := Color(0.20, 0.28, 0.40, 1.0)
@export var era_future_color := Color(0.06, 0.42, 0.58, 1.0)
## 现代时空文字的光晕（深字配浅边）
@export var modern_halo_color := Color(0.98, 0.98, 0.96, 0.80)
@export var font_size := 7

var _player: Node

func _ready() -> void:
	_player = get_node_or_null(player_path)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if _player == null:
		return

	# ---- 生命 ----
	var hp_max: float = _player.hp_max
	var hp: float = clampf(_player.hp, 0.0, hp_max)
	var hp_ratio: float = hp / hp_max if hp_max > 0.0 else 0.0
	var hp_col := hp_low_color if hp_ratio <= 0.3 else hp_color
	_draw_bar(hp_pos, hp_size, hp_ratio, hp_col, 4)
	var current_hp := str(int(round(hp))) if is_equal_approx(hp, round(hp)) else "%.1f" % hp
	var hp_text := "生命 %s/%d" % [current_hp, int(hp_max)]
	_draw_label(hp_pos + Vector2(hp_size.x + 4.0, hp_size.y), hp_text)
	_draw_era_label(hp_pos + Vector2(hp_size.x + 4.0, hp_size.y), hp_text)

	# ---- 韧性 ----
	var poise_max: float = _player.poise_max
	var poise: float = clampf(_player.poise, 0.0, poise_max)
	var poise_ratio: float = poise / poise_max if poise_max > 0.0 else 0.0
	var exhausted: bool = _player.is_exhausted()
	var poise_col := exhaust_color if exhausted else (poise_broken_color if poise <= 0.0 else poise_color)
	_draw_bar(poise_pos, poise_size, poise_ratio, poise_col, 4)
	_draw_label(poise_pos + Vector2(poise_size.x + 4.0, poise_size.y), "韧性 %d/%d" % [int(ceil(poise)), int(poise_max)])
	if exhausted:
		# 力竭：红字 + 一条倒计时细条
		var font := get_theme_default_font()
		var blink := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 120.0)
		draw_string(font, poise_pos + Vector2(poise_size.x + 4.0, poise_size.y + 10.0), "力竭",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(exhaust_label_color.r, exhaust_label_color.g, exhaust_label_color.b, blink))
		var ratio: float = _player.exhaust_ratio()
		var bar := Rect2(poise_pos + Vector2(0, poise_size.y + 2.0), Vector2(poise_size.x * ratio, 2.0))
		draw_rect(bar, Color(0.78, 0.22, 0.22, 0.85), true)

	# ---- 体力 ----
	var st_max: float = _player.stamina_max
	var st: float = clampf(_player.stamina, 0.0, st_max)
	var st_ratio: float = st / st_max if st_max > 0.0 else 0.0
	var st_col := stamina_color if _player.can_afford_dodge() else stamina_low_color
	var st_pos: Vector2 = Vector2(stamina_pos.x, get_viewport_rect().size.y + stamina_pos.y)
	_draw_bar(st_pos, stamina_size, st_ratio, st_col, 10)
	_draw_label(st_pos + Vector2(stamina_size.x + 4.0, stamina_size.y), "体力 %d/%d" % [int(floor(st)), int(st_max)])
	var claw_color := Color(0.45, 0.48, 0.53)
	if _player.has_claw:
		claw_color = Color(0.8, 0.35, 0.08) if _player.claw_cooldown_left > 0.0 else Color(0.08, 0.5, 0.3)
	var claw_pos := st_pos + Vector2(0, -6)
	_draw_halo_text(claw_pos, claw_status_text(), claw_color)
	draw_string(get_theme_default_font(), claw_pos, claw_status_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, claw_color)
	_draw_label(Vector2(get_viewport_rect().size.x - 115, 15), "Tab 天赋点 %d" % _player.talent_points)

func claw_status_text() -> String:
	if not _player.has_claw:
		return "钩爪 未获得"
	if _player.claw_cooldown_left > 0.0:
		return "钩爪 冷却 %.1fs" % (ceilf(_player.claw_cooldown_left * 10.0) / 10.0)
	return "钩爪 可用 [%s]" % Keybinds.key_text("claw")

func _draw_bar(pos: Vector2, bar_size: Vector2, ratio: float, fill: Color, segments: int) -> void:
	draw_rect(Rect2(pos, bar_size), empty_color, true)
	if ratio > 0.0:
		draw_rect(Rect2(pos, Vector2(bar_size.x * ratio, bar_size.y)), fill, true)
	if segments > 1:
		for i in range(1, segments):
			var x: float = pos.x + bar_size.x * float(i) / float(segments)
			draw_line(Vector2(x, pos.y), Vector2(x, pos.y + bar_size.y), Color(1, 1, 1, 0.55), 1.0)
	draw_rect(Rect2(pos, bar_size), border_color, false, 1.0)

## 在生命文字右边画当前时空（现代 / 未来）
func _draw_era_label(pos: Vector2, hp_text: String) -> void:
	var font := get_theme_default_font()
	var w: float = font.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var label := "现代"
	var col := era_modern_color
	# Timeline 是 autoload；测试/独立场景里可能没有，取不到就跳过
	var timeline := get_node_or_null("/root/Timeline")
	if timeline != null:
		label = timeline.era_name()
		col = era_future_color if timeline.is_future() else era_modern_color
	var lp := Vector2(pos.x + w + era_gap, pos.y - 1.0)
	_draw_halo_text(lp, label, col)
	draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

## HUD 文字颜色：两个时空都是深字 + 浅色描边（两套路面都偏浅）
func _label_color() -> Color:
	return label_color

func _draw_label(pos: Vector2, text: String) -> void:
	var font := get_theme_default_font()
	var col := _label_color()
	var p := Vector2(pos.x, pos.y - 1.0)
	_draw_halo_text(p, text, col)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

## 给文字描一圈反色边：现代=深字浅边，未来=浅字深边
func _draw_halo_text(pos: Vector2, text: String, col: Color) -> void:
	var font := get_theme_default_font()
	var halo: Color = modern_halo_color
	for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_string(font, pos + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, halo)
