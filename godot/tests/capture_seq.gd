extends Node
## 连续帧捕获：移动中逐帧保存画面，用来量化"角色是否抖动"。
## 用法：
##   godot --path godot res://tests/capture_seq.tscn -- --out=D:/shots/seq --frames=40 --press=move_down,move_right
##   --isolate        只留角色阴影（隐藏精灵、道具、HUD）
##   --isolate-player 只留角色精灵（隐藏道具、HUD、地面），用纯色背景测量角色屏幕位置
## 输出 f_000.png ... f_0NN.png + log.csv

var out_dir := ""
var frames := 40
var warmup := 90          # 先跑 90 个物理帧（约 1.5 秒）进入匀速
var press := ["move_right"]
var isolate := false          # 只显示阴影
var isolate_player := false   # 只显示角色
var isolate_ground := false   # 只显示地面网格

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--frames="):
			frames = int(a.trim_prefix("--frames="))
		elif a.begins_with("--warmup="):
			warmup = int(a.trim_prefix("--warmup="))
		elif a.begins_with("--press="):
			press = Array(a.trim_prefix("--press=").split(","))
		elif a == "--isolate":
			isolate = true
		elif a == "--isolate-player":
			isolate_player = true
		elif a == "--isolate-ground":
			isolate_ground = true
	if out_dir.is_empty():
		push_error("缺少 --out=目录")
		get_tree().quit(1)
		return

	var world: Node = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().physics_frame

	var ysort: Node2D = world.get_node("YSort")
	if isolate:
		# 只留角色的落地阴影（隐藏精灵、道具、HUD、地面），纯白背景便于精确测量
		for child in ysort.get_children():
			if child.name != "Player":
				child.visible = false
		ysort.get_node("Player/Sprite").visible = false
		world.get_node("HUD").visible = false
		world.get_node("Ground").visible = false
	elif isolate_player:
		# 只留角色精灵（隐藏道具、HUD、地面），纯白背景便于精确测量
		for child in ysort.get_children():
			if child.name != "Player":
				child.visible = false
		ysort.get_node("Player/Shadow").visible = false
		world.get_node("HUD").visible = false
		world.get_node("Ground").visible = false
	elif isolate_ground:
		# 只留地面网格（隐藏角色、道具、HUD），用来测量背景滚动是否均匀
		for child in ysort.get_children():
			child.visible = false
		world.get_node("HUD").visible = false

	for p in press:
		Input.action_press(p)
	for i in warmup:
		await get_tree().physics_frame

	DirAccess.make_dir_recursive_absolute(out_dir)
	var player: Node2D = world.get_node("YSort/Player")
	var cam: Camera2D = player.get_node("Camera")
	var csv := FileAccess.open(out_dir.path_join("log.csv"), FileAccess.WRITE)
	csv.store_line("frame,player_x,player_y,cam_center_x,cam_center_y")
	for i in frames:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("f_%03d.png" % i))
		var cam_center := cam.get_screen_center_position()
		csv.store_line("%d,%.4f,%.4f,%.4f,%.4f" % [
			i, player.global_position.x, player.global_position.y,
			cam_center.x, cam_center.y,
		])
	csv.close()

	for p in press:
		Input.action_release(p)
	print("[capture_seq] saved %d frames to %s" % [frames, out_dir])
	get_tree().quit(0)
