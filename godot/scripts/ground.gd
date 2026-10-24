extends Node2D
## 地面：默认是灰色底 + 方格参考线；设置了 `floor_texture` 时改用石材路面平铺。
## 放在世界最底层（z_index = -10），不参与 y-sort。

@export var world_rect := Rect2(-780, -470, 1560, 940)
@export var cell := 32.0
## 底色（灰底；有路面纹理时作为砖缝的底色）
@export var bg_color := Color(0.52, 0.53, 0.51, 1.0)
@export var line_color := Color(0.64, 0.67, 0.71, 1.0)
@export var accent_color := Color(0.56, 0.59, 0.64, 1.0)
@export var border_color := Color(0.48, 0.51, 0.56, 1.0)

@export_group("路面")
## 平铺的路面纹理（由 tools/build_road_tile.ps1 烘成的无缝小图）
@export var floor_texture: Texture2D
## 纹理在世界上重复的大小（像素）；默认用纹理本身尺寸
@export var floor_tile_scale := 1.0
## 路面整体亮度（1 = 原色；想压暗一点填 0.85 之类）
@export var floor_modulate := Color(1, 1, 1, 1)
## 没有纹理时是否画方格调试网格
@export var draw_grid := true

func _ready() -> void:
	# draw_texture_rect(tile=true) 需要开启纹理重复
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

func _draw() -> void:
	var r := world_rect
	# 铺底色
	draw_rect(r, bg_color, true)

	if floor_texture != null:
		_draw_floor(r)
	elif draw_grid:
		_draw_grid(r)

	# 外框
	draw_rect(r, border_color, false, 2.0)

## 石材路面：无缝纹理平铺（2:1 等距菱形铺石）
func _draw_floor(r: Rect2) -> void:
	var tile_size := Vector2(floor_texture.get_width(), floor_texture.get_height()) * floor_tile_scale
	var tile_rect := Rect2(r.position, r.size)
	# 让平铺图案和世界原点对齐，移动时不会"跳"
	var offset := Vector2(fposmod(r.position.x, tile_size.x), fposmod(r.position.y, tile_size.y))
	draw_set_transform(-offset)
	draw_texture_rect(floor_texture, Rect2(tile_rect.position, tile_rect.size + tile_size), true, floor_modulate)
	draw_set_transform(Vector2.ZERO)

func _draw_grid(r: Rect2) -> void:
	# 细网格
	var x := r.position.x
	while x <= r.end.x:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), line_color, 1.0)
		x += cell
	var y := r.position.y
	while y <= r.end.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), line_color, 1.0)
		y += cell

	# 每 4 格加深一次，强化透视参照
	x = r.position.x
	while x <= r.end.x:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), accent_color, 1.0)
		x += cell * 4.0
	y = r.position.y
	while y <= r.end.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), accent_color, 1.0)
		y += cell * 4.0
