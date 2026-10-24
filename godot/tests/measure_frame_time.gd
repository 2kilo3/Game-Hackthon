extends Node
## 帧间隔测量：跑若干秒，统计每帧耗时分布（判断高刷屏上的帧节奏是否均匀）。
## 用法：godot --path godot res://tests/measure_frame_time.tscn -- --seconds=3
## 只写 log，不截图。

var seconds := 3.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			seconds = float(a.trim_prefix("--seconds="))

	var world: Node = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().physics_frame

	# 移动起来，避免静止时帧率被 vsync 主导
	Input.action_press("move_right")
	Input.action_press("move_down")

	var deltas: Array[float] = []
	var t0 := Time.get_ticks_usec()
	var last := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < int(seconds * 1_000_000.0):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		deltas.append(float(now - last) / 1000.0)
		last = now
	Input.action_release("move_right")
	Input.action_release("move_down")

	if deltas.size() > 5:
		var sum := 0.0
		for d in deltas:
			sum += d
		var mean: float = sum / deltas.size()
		var sq := 0.0
		for d in deltas:
			sq += (d - mean) * (d - mean)
		var std := sqrt(sq / deltas.size())
		# 直方图：按 1ms 分桶
		var hist := {}
		for d in deltas:
			var key := int(floor(d))
			hist[key] = int(hist.get(key, 0)) + 1
		var keys := hist.keys()
		keys.sort()
		print("[frame_time] frames=%d  mean=%.2fms  fps=%.1f  std=%.2fms" % [
			deltas.size(), mean, 1000.0 / mean if mean > 0.0 else 0.0, std
		])
		var line := ""
		for k in keys:
			line += "%dms:%d  " % [k, hist[k]]
		print("[frame_time] histogram: ", line)
		print("[frame_time] display_refresh=", DisplayServer.screen_get_refresh_rate(), " max_fps=", Engine.max_fps)
	get_tree().quit(0)
