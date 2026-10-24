extends StaticBody2D
## 未来时空的能量桩：默认关闭（idle 循环）。
## 当"同一个位置"的现代花盆被打碎后，会播 activate 动画并转成 active 循环，
## 点亮后只协助攻击已经登场、仍然存活的未来 boss。

## 和现代花盆一一对应的编号（0 / 1 / 2）
@export var pot_index := 0
## 协助攻击的间隔（秒）
@export var attack_interval := 2.8
## 每次协助攻击造成的伤害（激光，不削韧性）
@export var attack_damage := 2.0
## 离 boss 多远才会帮忙打
@export var attack_range := 420.0

@onready var sprite: AnimatedSprite2D = $Sprite

var activated := false
## 调试/测试用：累计助攻次数
var attacks_made := 0

var _attack_timer := 0.0
var _attacking := false
var _attack_target: Node2D
var _attack_left := 0.0
var _attack_duration := 0.0
var _hit_done := false
## 激光显示剩余时间（画出从桩到 boss 的光束）
var _laser_left := 0.0
var _laser_target := Vector2.ZERO

func _ready() -> void:
	_show_static("idle")
	_attack_timer = attack_interval

## 平时只用一帧：多帧循环素材本身有细微抖动，静止时定格第一帧最稳
func _show_static(anim: String) -> void:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim):
		return
	sprite.play(anim)
	sprite.pause()
	sprite.frame = 0

func _physics_process(delta: float) -> void:
	if _attack_target != null and not _is_assist_target(_attack_target):
		_cancel_attack()
	if _laser_left > 0.0:
		_laser_left = maxf(0.0, _laser_left - delta)
		queue_redraw()
		if _laser_left <= 0.0:
			z_index = 0
	if not activated:
		var w := _world()
		if w != null and w.has_method("is_pot_broken") and bool(w.is_pot_broken(pot_index)):
			_activate()
		return

	if _attacking:
		_update_attack(delta)
		return

	if _find_boss() == null:
		_attack_timer = attack_interval
		return
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_interval
	_try_attack()

## 花盆碎了 → 启动：播 activate，播完转 active 循环
func _activate() -> void:
	activated = true
	sprite.play("activate")
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("activate"):
		var fps: float = sprite.sprite_frames.get_animation_speed("activate")
		var cnt: int = sprite.sprite_frames.get_frame_count("activate")
		var wait: float = (float(cnt) / maxf(fps, 0.001))
		await get_tree().create_timer(wait, false).timeout
	if activated and not _attacking:
		_show_static("active")

## 蓄力和命中都在物理帧推进，取消后不会遗留延迟命中回调。
func _try_attack() -> void:
	if _attacking or not activated or not is_visible_in_tree():
		return
	var boss := _find_boss()
	if boss == null:
		return
	_cancel_attack()
	_attack_target = boss
	_attack_target.died.connect(_cancel_attack)
	_attack_target.tree_exiting.connect(_cancel_attack)
	_attacking = true
	sprite.play("attack")
	var fps: float = 14.0
	var cnt := 6
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("attack"):
		fps = sprite.sprite_frames.get_animation_speed("attack")
		cnt = sprite.sprite_frames.get_frame_count("attack")
	_attack_duration = float(cnt) / maxf(fps, 0.001)
	_attack_left = _attack_duration
	_hit_done = false

func _update_attack(delta: float) -> void:
	_attack_left = maxf(0.0, _attack_left - delta)
	if not _hit_done and _attack_left <= _attack_duration * 0.5:
		_hit_done = true
		_laser_left = 0.55
		_laser_target = _attack_target.global_position + Vector2(0, -20)
		_attack_target.take_laser_damage(attack_damage)
		attacks_made += 1
		queue_redraw()
	if _attacking and _attack_left <= 0.0:
		_attacking = false
		_show_static("active")

func _cancel_attack() -> void:
	if is_instance_valid(_attack_target):
		for signal_name in ["died", "tree_exiting"]:
			if _attack_target.is_connected(signal_name, _cancel_attack):
				_attack_target.disconnect(signal_name, _cancel_attack)
	_attack_target = null
	_attacking = false
	_attack_left = 0.0
	_hit_done = false
	_laser_left = 0.0
	_laser_target = Vector2.ZERO
	_attack_timer = attack_interval
	z_index = 0
	if activated and is_instance_valid(sprite):
		_show_static("active")
	queue_redraw()

func _is_assist_target(boss) -> bool:
	return is_instance_valid(boss) and boss is Node2D \
		and boss.is_in_group("future_boss") and boss.has_signal("died") and boss.has_method("take_laser_damage") \
		and boss.is_visible_in_tree() and boss.process_mode != Node.PROCESS_MODE_DISABLED \
		and not bool(boss.get("dead")) and float(boss.get("hp")) > 0.0 \
		and global_position.distance_to(boss.global_position) <= attack_range

func _find_boss() -> Node2D:
	var best: Node2D = null
	var best_dist: float = attack_range + 1.0
	for n in get_tree().get_nodes_in_group("future_boss"):
		if not _is_assist_target(n):
			continue
		var d: float = global_position.distance_to((n as Node2D).global_position)
		if d <= attack_range and d < best_dist:
			best = n
			best_dist = d
	return best

func _world() -> Node:
	var p := get_parent()
	if p != null:
		return p.get_parent()
	return null

func _draw() -> void:
	if _laser_left <= 0.0:
		return
	# _draw 用的是本地坐标：起点=桩顶，终点=目标转本地
	var from := Vector2(0, -38)
	var to := _laser_target - global_position
	var t: float = clampf(_laser_left / 0.55, 0.0, 1.0)
	z_index = 30
	# 外发光 + 主体 + 白色核心，尽量显眼
	draw_line(from, to, Color(0.25, 0.85, 1.0, 0.35 * t), 11.0)
	draw_line(from, to, Color(0.45, 0.95, 1.0, 0.85 * t), 6.0)
	draw_line(from, to, Color(1, 1, 1, 0.95 * t), 2.5)
	draw_circle(from, 9.0 * t, Color(0.6, 0.95, 1.0, 0.75 * t))
	draw_circle(to, 12.0 * t, Color(0.5, 0.9, 1.0, 0.55 * t))
	draw_circle(to, 6.0 * t, Color(1, 1, 1, 0.9 * t))
