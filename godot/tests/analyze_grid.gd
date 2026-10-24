extends SceneTree
## 分析背景网格在连续截图中的滚动步长（判断是否均匀）。
## 用法：
##   godot --headless --script res://tests/analyze_grid.gd -- --dir=D:/seq --frames=30
## 做法：取一条水平扫描行，用周期 96px 的离散傅里叶相位求网格的亚像素偏移。

var dir := ""
var frames := 30
var row := 300
var cell := 96.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.trim_prefix("--dir=")
		elif a.begins_with("--frames="):
			frames = int(a.trim_prefix("--frames="))
		elif a.begins_with("--row="):
			row = int(a.trim_prefix("--row="))
	if dir.is_empty():
		print("缺少 --dir=")
		quit(1)
		return

	var phases: Array[float] = []
	for i in frames:
		var p := "%s/f_%03d.png" % [dir, i]
		if not FileAccess.file_exists(p):
			break
		phases.append(_phase_of(p))

	if phases.size() < 5:
		print("样本不足: ", phases.size())
		quit(1)
		return

	# 展开相位
	var unwrapped: Array[float] = []
	var carry := 0.0
	var prev := NAN
	for ph in phases:
		if not is_nan(prev):
			var raw: float = ph - prev
			if raw > cell * 0.5:
				carry -= cell
			elif raw < -cell * 0.5:
				carry += cell
		unwrapped.append(ph + carry)
		prev = ph

	# 步长
	var steps: Array[float] = []
	for i in range(1, unwrapped.size()):
		steps.append(unwrapped[i] - unwrapped[i - 1])

	var sum := 0.0
	for s in steps:
		sum += s
	var mean: float = sum / float(steps.size())
	var max_dev := 0.0
	var sum_dev := 0.0
	for s in steps:
		var d: float = absf(s - mean)
		max_dev = maxf(max_dev, d)
		sum_dev += d
	var avg_dev: float = sum_dev / float(steps.size())

	var line := ""
	for s in steps:
		line += "%.2f " % s
	print("[grid] frames=%d  mean step=%.3f px/frame  max|dev|=%.2f  avg|dev|=%.2f" % [
		phases.size(), mean, max_dev, avg_dev
	])
	print("[grid] steps: ", line)
	print("[grid] verdict: ", "EVEN" if max_dev <= 1.0 else "UNEVEN")
	quit(0)

## 用 DFT 相位求网格在该行的亚像素位置
func _phase_of(path: String) -> float:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		push_error("读取失败: " + path)
		return 0.0
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var sum_sin := 0.0
	var sum_cos := 0.0
	for x in w:
		var c := img.get_pixel(x, row)
		var d := 1.0 - c.r          # 白底上的暗线强度
		if d <= 0.001:
			continue
		var ang := TAU * float(x) / cell
		sum_sin += d * sin(ang)
		sum_cos += d * cos(ang)
	var ph := atan2(sum_sin, sum_cos)
	if ph < 0.0:
		ph += TAU
	return ph / TAU * cell
