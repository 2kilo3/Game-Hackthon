extends Node
## 临时工具：打印现代地图的可走区域（ASCII），用来选三个路口的坐标。
## 运行：godot --headless --path godot res://tests/dump_walkable.tscn

func _ready() -> void:
	var world: Node = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	# 打印现代地图
	await get_tree().process_frame
	world._apply_era()
	await get_tree().process_frame
	world._build_air_walls(world.modern_map)
	var tiles: Array = []
	world._collect_map_tiles(world.modern_map, tiles)
	var cell := 32.0
	var x0 := -760.0
	var y0 := -440.0
	var cols := 48
	var rows := 28
	print("[map] 现代地图可走区域（# = 地板, . = 空）")
	print("[map] x 从 %.0f 到 %.0f，y 从 %.0f 到 %.0f，每格 %.0f px" % [x0, x0 + cols * cell, y0, y0 + rows * cell, cell])
	var header := "        "
	for c in range(cols):
		header += str(int((x0 + c * cell) / 64.0) % 10)
	print(header)
	for r in range(rows):
		var line := "%6.0f  " % (y0 + r * cell)
		for c in range(cols):
			var p := Vector2(x0 + (c + 0.5) * cell, y0 + (r + 0.5) * cell)
			line += "#" if world._has_floor_pixel(tiles, p) else "."
		print(line)
	var cands: Array[Vector2] = [
		Vector2(-420, -60), Vector2(-100, -200), Vector2(300, -150), Vector2(-160, 200),
		Vector2(200, 0), Vector2(0, 0), Vector2(-200, 0), Vector2(0, 120),
		Vector2(400, -40), Vector2(-320, -160), Vector2(-320, 160), Vector2(-120, -80),
	]
	for cand in cands:
		print("[cand] (%.0f, %.0f) walkable=%s inside=%s" % [cand.x, cand.y, str(world._has_floor_pixel(tiles, cand)), str(world.is_inside_play_area(cand))])
	print("[hull] " + str(world._hull_points))
	# 顺便打印地图范围
	print("[map] modern_map 范围 = ", str(world._map_rect_for(world.modern_map)))
	get_tree().quit(0)
