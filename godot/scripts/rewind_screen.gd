extends CanvasLayer
## 死亡回溯表现：全屏渐黑 → 居中显示「时间回溯」→ 再渐亮。
##
## 只管表现，不管复活：由 world.gd 触发 play()，收到 finished 信号后再把角色放回出生点。

signal covered    ## 画面已经完全变黑（此时适合复位角色，玩家看不到瞬移）
signal finished   ## 已经淡出结束

@export var fade_in := 0.32
@export var hold := 0.9
@export var fade_out := 0.45
## 文字出现时的轻微缩放（1.0 = 不动）
@export var text_scale_from := 1.15

@onready var black: ColorRect = $Black
@onready var label: Label = $Label

var _playing := false

func _ready() -> void:
	visible = false
	label.text = "时间回溯"

func play() -> void:
	if _playing:
		return
	_playing = true
	visible = true
	black.color = Color(0, 0, 0, 0)
	label.modulate = Color(1, 1, 1, 0)
	label.pivot_offset = label.size * 0.5

	var tween := create_tween()
	tween.tween_property(black, "color:a", 1.0, fade_in)
	tween.parallel().tween_property(label, "modulate:a", 1.0, fade_in)
	# 画面已经全黑：这时候再做复活/复位，玩家看不到角色瞬移
	tween.tween_callback(func() -> void: covered.emit())
	tween.tween_interval(hold)
	tween.tween_property(black, "color:a", 0.0, fade_out)
	tween.parallel().tween_property(label, "modulate:a", 0.0, fade_out)
	tween.tween_callback(func() -> void:
		visible = false
		_playing = false
		finished.emit()
	)

func is_playing() -> bool:
	return _playing
