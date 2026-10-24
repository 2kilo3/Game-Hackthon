extends Node2D
signal pot_destroyed
signal future_boss_appeared
## 世界：地图 / 空气墙 / 墙体遮挡 / 死亡回溯 / 截图捕获（给自动化验证用）。
## 游戏逻辑都在 player.gd / shadow.gd 里。

@onready var player: CharacterBody2D = $YSort/Player
@onready var debug_label: Label = $HUD/Debug
@onready var hint_label: Label = $HUD/Hint
@onready var ysort: Node2D = $YSort
@onready var rewind: CanvasLayer = $RewindScreen
@onready var settings: CanvasLayer = $SettingsMenu
@onready var talents: CanvasLayer = $TalentMenu
@onready var ground: Node2D = $Ground
@onready var modern_map: Node2D = $ModernMap
@onready var future_map: Node2D = $FutureMap
@onready var walls: Node2D = $Walls
## 两个时空各自的生物（测试桩）；切换时空时整组启用/禁用，状态互不影响
@onready var _entities_modern: Array[Node] = [$"YSort/ModernEnemy", $"YSort/ModernEnemy2", $"YSort/ModernEnemy3", $"YSort/ModernBoss"]
@onready var _entities_future: Array[Node] = [$"YSort/FutureEnemy", $"YSort/FutureEnemy2", $"YSort/FutureEnemy3", $"YSort/FutureEnemy4", $"YSort/FutureEnemy5"]

## 两个时空的地图纹理（备用，现在都用等距地图场景）
@export var modern_floor: Texture2D
@export var future_floor: Texture2D

var show_hint := true
## 出生点（复活用）；默认取角色在场景里的初始位置
var spawn_position := Vector2.ZERO
var _rewinding := false
## 截图调试：把空气墙矩形画成红线
var _debug_walls := false
## 截图调试：打印每帧相机/角色位置，用来查抖动
var _jitter_log := false

func _ready() -> void:
	debug_label.visible = false   # F1 打开
	hint_label.text = "WASD 移动 Shift/L 闪避 J 普攻 K 格挡 R 时空 Tab 天赋 Esc 设置"
	spawn_position = player.global_position
	rewind.covered.connect(_on_rewind_covered)
	player.death_animation_finished.connect(_start_rewind)
	player.era_shift_midpoint.connect(_on_era_shift_midpoint)
	settings.opened.connect(_on_settings_opened)
	settings.closed.connect(_on_settings_closed)
	talents.opened.connect(_on_settings_opened)
	talents.closed.connect(_on_settings_closed)
	player.talents_changed.connect($HUD/StatusBars.queue_redraw)
	player.claw_unlocked.connect(_on_claw_picked_up)
	for enemy in _entities_modern + _entities_future:
		if enemy.name == "ModernBoss":
			enemy.defeated.connect(_on_modern_boss_defeated)
		else:
			enemy.defeated.connect(player.add_talent_points.bind(1))
	$YSort/FutureBoss.died.connect(player.add_talent_points.bind(2))
	rewind.finished.connect(_on_rewind_finished)
	Timeline.era_changed.connect(_on_era_changed)
	_apply_era()
	_setup_wall_views()
	_capture_if_requested()
	if ResourceLoader.exists("res://addons/time_bureau_menu/main_menu.tscn") and ResourceLoader.exists("res://scenes/main_menu.tscn"):
		settings.add_footer_button("主菜单", _return_to_main_menu)

## 场景切换释放整局（包括子弹、敌人、道具和 HUD），不保留旧 World。
func _return_to_main_menu() -> void:
	settings.close()
	var err := get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if err != OK:
		push_error("返回主菜单失败：%s" % error_string(err))

func _unhandled_input(event: InputEvent) -> void:
	# Esc 打开设置界面（关闭由界面自己处理，因为暂停后只有它能收输入）
	if event.is_action_pressed("toggle_settings") and not settings.is_open():
		if talents.is_open():
			return
		settings.open()
		return
	if event.is_action_pressed("toggle_debug"):
		debug_label.visible = not debug_label.visible
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		# F2：重置主角状态（调试用）
		player.reset_stats()
	if event.is_action_pressed("debug_damage"):
		player.hurt_invuln_left = 0.0
		player.take_damage(5.0)
	if event.is_action_pressed("debug_poise"):
		player.poise = maxf(0.0, player.poise - 20.0)
	if event.is_action_pressed("debug_heal"):
		player.reset_stats()   # F5：生命 / 韧性 / 体力全满
	if event.is_action_pressed("debug_kill") and not _rewinding:
		player.kill()
	if event.is_action_pressed("debug_hit_dummy"):
		var dummy: Node = ysort.get_node_or_null("TestDummy")
		if dummy != null:
			dummy.take_damage(20.0)
			dummy.damage_poise(10.0)

## 时空切换：换地图 / 空气墙 / 生物
func _on_era_changed(_era: int) -> void:
	# 飞行物挂在 YSort，必须在切换时清理，不能只检查敌人的子节点。
	for effect in ysort.get_children():
		if effect.is_in_group("era_projectile"):
			effect.hide()
			effect.process_mode = Node.PROCESS_MODE_DISABLED
			effect.queue_free()
	player.cam_focus_left = 0.0
	player.cam_focus_target = null
	_apply_era()
	if Timeline.is_future() and is_instance_valid(_boss_transform_actor):
		player.focus_camera_on(_boss_transform_actor.global_position, _boss_transform_actor.remaining_seconds(), _boss_transform_actor)
	_setup_wall_views()

## 消失播完的那一刻才真正切换时空（出现动画在另一个时空里倒放）
func _on_era_shift_midpoint() -> void:
	Timeline.toggle()

func _apply_era() -> void:
	var future := Timeline.is_future()
	if modern_map != null:
		modern_map.visible = not future
	if future_map != null:
		future_map.visible = future
	# 两个时空都是"浮空地图"，地面只留深色底
	var bg := Color(0.07, 0.09, 0.13, 1.0) if future else Color(0.13, 0.12, 0.11, 1.0)
	if ground != null:
		ground.floor_texture = null
		ground.draw_grid = false
		ground.bg_color = bg
		ground.queue_redraw()
	RenderingServer.set_default_clear_color(bg)
	_set_walls_enabled(false)
	var active: Node2D = _map_of(future)
	# 两个时空共用同一套空气墙（用现代地图的位置生成）：切换时空时墙不动，避免穿墙
	if _shared_walls == null:
		_build_air_walls(modern_map)
	_set_air_walls_enabled(modern_map, true)
	_apply_camera_limits_to(active)
	_set_era_entities(future)
	_refresh_era_props()

func _draw() -> void:
	if not _debug_walls:
		return
	var body: StaticBody2D = air_walls_of(Timeline.is_future())
	if body == null:
		return
	for child in body.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape is RectangleShape2D:
			var cs: CollisionShape2D = child
			var size: Vector2 = (cs.shape as RectangleShape2D).size
			var r := Rect2(cs.position - size * 0.5, size)
			draw_rect(r, Color(1.0, 0.15, 0.15, 0.9), false, 1.5)

## 花盆被打碎时由 flower_pot.gd 调用
func mark_pot_broken(idx: int) -> void:
	if idx >= 0 and idx < pot_broken.size() and not pot_broken[idx]:
		pot_broken[idx] = true
		pot_destroyed.emit()
	# 这里不要调 _refresh_era_props()：刚碎的花盆还要播破碎动画，不能被立刻隐藏

func is_pot_broken(idx: int) -> bool:
	if idx >= 0 and idx < pot_broken.size():
		return pot_broken[idx]
	return false

## 按当前时空显示/隐藏 花盆（现代）与 能量桩（未来）
## boss 是否已经入场
var boss_entered := false
var modern_boss_defeated := false

## 入场条件：现代与未来的普通敌人全部死亡 + 现代 boss 已被击败。
## 入场条件是否满足（外部/测试可直接查询）
func is_boss_entrance_ready() -> bool:
	if boss_entered or _boss_transform_running or not modern_boss_defeated or not Timeline.is_future():
		return false
	if player == null or player.is_dead():
		return false
	for e in _entities_modern + _entities_future:
		if not is_instance_valid(e):
			continue
		var d = e.get("dead")
		if d == null:
			continue
		if not bool(d):
			return false
	return true

## 现代 boss 出场：现代普通敌人（不含 boss）全部消灭后，缓缓走出
func _check_modern_boss_entrance() -> void:
	if Timeline.is_future() or modern_boss_defeated:
		return
	var mb: Node = ysort.get_node_or_null("ModernBoss")
	if mb == null or bool(mb.dead) or bool(mb.spawned) or bool(mb._entering):
		return
	for e in _entities_modern:
		if e == mb or not is_instance_valid(e):
			continue
		var d = e.get("dead")
		if d == null:
			continue
		if not bool(d):
			return   # 还有普通敌人活着
	mb.begin_entrance()
	_set_entity_active(mb, true)
	player.focus_camera_on((mb as Node2D).global_position, 1.5, mb)
	print("[world] 现代普通敌人清空，现代 boss 出场")

## 未来 boss 出场：现代 boss 走出并变身
var _boss_transform_actor: Node = null
var _boss_transform_running := false

func _start_future_boss_transform() -> void:
	var boss: Node2D = ysort.get_node_or_null("FutureBoss")
	if not Timeline.is_future() or boss_entered or _boss_transform_running or boss == null or boss._entered or boss.dead:
		return
	boss_entered = true
	_boss_transform_running = true
	_set_entity_active(boss, false)
	var actor: Node2D = load("res://scripts/boss_transform.gd").new()
	actor.name = "BossTransformActor"
	actor.position = boss.position
	var modern: Node = ysort.get_node_or_null("ModernBoss")
	if modern != null:
		actor.entrance_walk_seconds = modern.entrance_walk_seconds
		actor.walk_speed = modern.walk_speed
	_boss_transform_actor = actor
	actor.finished.connect(_on_boss_transform_finished.bind(actor))
	ysort.add_child(actor)
	player.focus_camera_on(actor.global_position, actor.remaining_seconds(), actor)

func _on_boss_transform_finished(actor: Node2D) -> void:
	if actor != _boss_transform_actor or not Timeline.is_future():
		return
	var boss: Node2D = ysort.get_node_or_null("FutureBoss")
	if boss != null and not boss.dead:
		boss.global_position = actor.global_position
		boss.begin_entrance()
		_set_entity_active(boss, true)
		player.focus_camera_on(boss.global_position, 0.8, boss)
		future_boss_appeared.emit()
	actor.hide()
	actor.queue_free()
	_boss_transform_actor = null
	_boss_transform_running = false

func _check_boss_entrance() -> void:
	if is_boss_entrance_ready():
		_start_future_boss_transform()


func _refresh_era_props() -> void:
	var future := Timeline.is_future()
	for i in range(3):
		var pot: Node = ysort.get_node_or_null("FlowerPot%d" % (i + 1))
		if pot != null:
			# 已经碎掉的花盆不强行改可见性（正在播破碎动画 / 已播完自己隐藏）
			if not is_pot_broken(i):
				pot.visible = not future
			pot.set_physics_process(not future)
			# 只有"现代 + 没碎"的花盆才挡路
			var pot_solid: bool = (not future) and (not is_pot_broken(i))
			pot.set_deferred("collision_layer", 1 if pot_solid else 0)
			pot.set_deferred("collision_mask", 1 if pot_solid else 0)
		var pylon: Node = ysort.get_node_or_null("EnergyPylon%d" % (i + 1))
		if pylon != null:
			pylon.visible = future
			pylon.set_physics_process(future)
			# 隐藏的能量桩不能有碰撞，否则会在现代的地面上凭空挡人
			pylon.set_deferred("collision_layer", 1 if future else 0)
			pylon.set_deferred("collision_mask", 1 if future else 0)

func _map_of(future: bool) -> Node2D:
	return future_map if future else modern_map

# ---------------- 地图 / 空气墙 ----------------
var _air_walls := {}          # map_node -> StaticBody2D
var _shared_walls: StaticBody2D = null   # 两个时空共用的空气墙（用现代地图生成）
var _wall_views := {}         # map_node -> [{sp, base_y, cx, half_w, h, size}]，用于遮挡排序与虚化

## 收集地图里的地砖（不含墙体/物件）：记下贴图、世界位置和尺寸
const FLOOR_SAMPLE_TOP := 18.0    # 只采样顶面：128×128 贴图里菱形顶面大约在 y=18..82
const FLOOR_SAMPLE_BOTTOM := 82.0

func _collect_map_tiles(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Sprite2D and child.texture != null and String(child.get_meta("meowa_kind", "tile")) == "tile":
			var sp: Sprite2D = child
			# 台阶/下沉区的砖不算"可走地板"，否则玩家能走进路口下面的凹坑
			if String(sp.texture.resource_path).contains("b0bpvqxjfs6"):
				continue
			var img: Image = sp.texture.get_image()
			if img == null:
				continue
			# 每张贴图的顶面起始行不一样（不同 tile 变体），按第一行不透明像素算
			var band_top := -1
			for y in range(img.get_height()):
				var found := false
				for x in range(0, img.get_width(), 4):
					if img.get_pixel(x, y).a > 0.3:
						found = true
						break
				if found:
					band_top = y
					break
			if band_top < 0:
				continue
			out.append({
				"pos": sp.global_position,
				"img": img,
				"w": img.get_width(),
				"h": img.get_height(),
				"top": band_top,
			})
		_collect_map_tiles(child, out)

## 点下面是否真的有一块地砖（直接采样贴图像素，比菱形近似更贴合地图）
## 采样点偏移：单点采样会在地砖接缝的透明像素上误判，所以按 3×3 小范围取最大值
const FLOOR_SAMPLE_OFFSETS: Array[Vector2] = [
	Vector2.ZERO,
	Vector2(-8, 0), Vector2(8, 0), Vector2(0, -8), Vector2(0, 8),
	Vector2(-8, -8), Vector2(8, -8), Vector2(-8, 8), Vector2(8, 8),
]

## 点下面是否真的有一块地砖（直接采样贴图像素，比菱形近似更贴合地图）
func _has_floor_pixel(tiles: Array, p: Vector2) -> bool:
	for off in FLOOR_SAMPLE_OFFSETS:
		var q: Vector2 = p + off
		for t in tiles:
			var local: Vector2 = q - (t["pos"] as Vector2)
			if local.x < 0.0 or local.y < 0.0 or local.x >= float(t["w"]) or local.y >= float(t["h"]):
				continue
			var band_top: float = float(t["top"])
			if local.y < band_top or local.y > band_top + 96.0:
				continue
			var col: Color = (t["img"] as Image).get_pixel(int(local.x), int(local.y))
			if col.a > 0.3:
				return true
	return false
## 收集地图里的墙体/物件（meowa_kind = "object"）的**底部占地**矩形
## 墙体贴图很高（128 或 86×170），真正挡人的只有贴图底部那一条
## 世界坐标是否在栅栏围成的可玩区域内（比"有地板"更严格：留 24px 内缩，避免站在台沿/栅栏上）
func is_inside_play_area(p: Vector2) -> bool:
	if _hull_points.size() < 3:
		return true
	var margin := 24.0
	if not _point_in_polygon(p, _hull_points):
		return false
	for off: Vector2 in [Vector2(margin, 0), Vector2(-margin, 0), Vector2(0, margin), Vector2(0, -margin)]:
		if not _point_in_polygon(p + off, _hull_points):
			return false
	return true

func _point_in_polygon(p: Vector2, poly: Array[Vector2]) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in range(n):
		var a := poly[i]
		var b := poly[j]
		if ((a.y > p.y) != (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside

## 世界坐标是否在可走地面上（给敌人在巡逻/追击时判边界用）
var _tile_cache := {}   # map_node -> [tiles]
## 栅栏围成的凸包（可玩区域外框），用来挡住"走到台面边缘/栅栏外"的敌人
var _hull_points: Array[Vector2] = []
## 三个花盆是否已被打碎（未来时空的能量桩据此启动）
var pot_broken: Array[bool] = [false, false, false]

func is_walkable_point(p: Vector2) -> bool:
	var map: Node2D = _map_of(Timeline.is_future())
	if map == null:
		return false
	var tiles: Array = _tile_cache.get(map, [])
	if tiles.is_empty():
		_collect_map_tiles(map, tiles)
		_tile_cache[map] = tiles
	if tiles.is_empty():
		return false
	if _has_floor_pixel(tiles, p):
		return true
	# 脚下正好踩在地砖接缝/边缘时，允许一点容差（往周围再探一圈）
	for off in FLOOR_SAMPLE_OFFSETS:
		if _has_floor_pixel(tiles, p + off * 3.0):
			return true
	return false


func _collect_map_walls(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Sprite2D and child.texture != null and String(child.get_meta("meowa_kind", "")) == "object":
			var size: Vector2 = child.texture.get_size()
			var s: Vector2 = child.global_scale.abs()
			var bottom: Vector2 = child.to_global(Vector2(size.x * 0.5, size.y))
			var half_w: float = size.x * 0.5 * s.x
			var base_h: float = minf(48.0 * s.y, size.y * s.y * 0.5)
			out.append(Rect2(Vector2(bottom.x - half_w, bottom.y - base_h), Vector2(half_w * 2.0, base_h)))
		_collect_map_walls(child, out)

## 某张地图的地砖覆盖范围（所有地砖贴图矩形的并集外框）
func _map_rect_for(map_node: Node2D) -> Rect2:
	if map_node == null:
		return Rect2()
	var tiles: Array = []
	_collect_map_tiles(map_node, tiles)
	if tiles.is_empty():
		return Rect2()
	var first: Dictionary = tiles[0]
	var bounds := Rect2(first["pos"], Vector2.ZERO)
	for t in tiles:
		var pos: Vector2 = t["pos"]
		var size := Vector2(float(t["w"]), float(t["h"]))
		bounds = bounds.expand(pos)
		bounds = bounds.expand(pos + size)
	return bounds

## 当前时空的地图范围
func _map_rect() -> Rect2:
	return _map_rect_for(_map_of(Timeline.is_future()))

## 按地图地砖顶面生成空气墙（没铺地砖的地方挡住），每张地图一份
## 凸包（Andrew monotone chain）
func _convex_hull(pts: Array[Vector2]) -> Array[Vector2]:
	var a := pts.duplicate()
	a.sort_custom(func(p: Vector2, q: Vector2) -> bool:
		if p.x == q.x:
			return p.y < q.y
		return p.x < q.x)
	var cross := func(o: Vector2, p: Vector2, q: Vector2) -> float:
		return (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x)
	var lower: Array[Vector2] = []
	for p in a:
		while lower.size() >= 2 and cross.call(lower[lower.size() - 2], lower[lower.size() - 1], p) <= 0.0:
			lower.remove_at(lower.size() - 1)
		lower.append(p)
	var upper: Array[Vector2] = []
	for i in range(a.size() - 1, -1, -1):
		var p: Vector2 = a[i]
		while upper.size() >= 2 and cross.call(upper[upper.size() - 2], upper[upper.size() - 1], p) <= 0.0:
			upper.remove_at(upper.size() - 1)
		upper.append(p)
	lower.remove_at(lower.size() - 1)
	upper.remove_at(upper.size() - 1)
	var hull: Array[Vector2] = []
	for p in lower:
		hull.append(p)
	for p in upper:
		hull.append(p)
	return hull

## 空气墙：沿"用户画的方框"围一圈 —— 取所有栅栏/墙体底部点的凸包外轮廓
func _build_air_walls(map_node: Node2D) -> void:
	if map_node == null or _air_walls.has(map_node):
		return
	var wall_foot: Array = []
	_collect_map_walls(map_node, wall_foot)
	var bounds: Rect2 = _map_rect_for(map_node)
	if wall_foot.is_empty():
		return
	var body := StaticBody2D.new()
	body.name = "AirWalls"
	add_child(body)
	var count := 0
	# 1) 收集所有栅栏底部点（取底部中心，去重）
	var pts: Array[Vector2] = []
	for r in wall_foot:
		var rr: Rect2 = r
		var c := Vector2(rr.get_center().x, rr.position.y - 20.0)
		var dup := false
		for q in pts:
			if q.distance_to(c) < 10.0:
				dup = true
				break
		if not dup:
			pts.append(c)
	# 2) 原有墙壁：沿栅栏的线段（相邻栅栏底部点两两相连）—— 保持不变
	for i in range(pts.size()):
		for j in range(i + 1, pts.size()):
			var d0: float = pts[i].distance_to(pts[j])
			if d0 <= 6.0 or d0 > 110.0:
				continue
			var wshape := RectangleShape2D.new()
			wshape.size = Vector2(d0 + 20.0, 10.0)
			var wcol := CollisionShape2D.new()
			wcol.shape = wshape
			wcol.position = (pts[i] + pts[j]) * 0.5
			wcol.rotation = (pts[j] - pts[i]).angle()
			body.add_child(wcol)
			count += 1

	# 2) 凸包 = 最外一圈（就是用户画的方框）
	var hull := _convex_hull(pts)
	_hull_points = hull   # 存下来给"是否在栅栏范围内"用
	# 3) 沿凸包每一条边放一个带旋转的细矩形碰撞体，首尾相连
	for i in range(hull.size()):
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i + 1) % hull.size()]
		if a.distance_to(b) < 4.0:
			continue
		var sshape := RectangleShape2D.new()
		sshape.size = Vector2(a.distance_to(b) + 24.0, 12.0)
		var scol := CollisionShape2D.new()
		scol.shape = sshape
		scol.position = (a + b) * 0.5
		scol.rotation = (b - a).angle()
		body.add_child(scol)
		count += 1
	# 4) 兜底：地图范围外再围一圈（万一凸包有缝）
	var guard_rects: Array[Rect2] = [
		Rect2(bounds.position.x - 120.0, bounds.position.y - 120.0, bounds.size.x + 240.0, 64.0),
		Rect2(bounds.position.x - 120.0, bounds.end.y + 56.0, bounds.size.x + 240.0, 64.0),
		Rect2(bounds.position.x - 120.0, bounds.position.y - 120.0, 64.0, bounds.size.y + 240.0),
		Rect2(bounds.end.x + 56.0, bounds.position.y - 120.0, 64.0, bounds.size.y + 240.0),
	]
	for gr in guard_rects:
		var gshape := RectangleShape2D.new()
		gshape.size = gr.size
		var gcol := CollisionShape2D.new()
		gcol.shape = gshape
		gcol.position = gr.get_center()
		body.add_child(gcol)
		count += 1
	body.set_meta("wall_count", count)
	body.set_meta("bounds", bounds)
	_air_walls[map_node] = body
	_shared_walls = body
	print("[airwall] %s hull=%d walls=%d fences=%d" % [String(map_node.name), hull.size(), count, wall_foot.size()])

func pts_count(arr: Array) -> int:
	return arr.size()

func walkable_count_total(arr: PackedByteArray) -> int:
	var n := 0
	for v in arr:
		if v == 1:
			n += 1
	return n

func _set_air_walls_enabled(_map_node: Node2D, enabled: bool) -> void:
	var body: StaticBody2D = _shared_walls
	if body == null:
		return
	body.collision_layer = 1 if enabled else 0
	body.collision_mask = 1 if enabled else 0
## 取某个时空那套空气墙（测试用）
## 取空气墙（两个时空共用一套，测试用）
func air_walls_of(_future: bool) -> StaticBody2D:
	return _shared_walls

## 相机范围按该地图的实际范围
func _apply_camera_limits_to(map_node: Node2D) -> void:
	var cam: Camera2D = player.get_node_or_null("Camera")
	if cam == null:
		return
	var bounds: Rect2 = _map_rect_for(map_node)
	if bounds.size.x <= 0.0:
		return
	cam.limit_left = int(bounds.position.x) - 8
	cam.limit_top = int(bounds.position.y) - 8
	cam.limit_right = int(bounds.end.x) + 8
	cam.limit_bottom = int(bounds.end.y) + 8

# ---------------- 墙壁与角色的遮挡 ----------------
## 收集墙体精灵（墙体是单独的 Sprite2D，meowa_kind = "object"）
func _collect_wall_sprites(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Sprite2D and child.texture != null and String(child.get_meta("meowa_kind", "")) == "object":
			var sp: Sprite2D = child
			sp.z_as_relative = false   # z_index 用绝对深度，和主角同一条时间线
			var size: Vector2 = sp.texture.get_size() * sp.global_scale.abs()
			out.append({
				"sp": sp,
				"base_y": sp.global_position.y + size.y,
				"cx": sp.global_position.x + size.x * 0.5,
				"half_w": size.x * 0.5,
				"h": size.y,
				"size": size,
			})
		_collect_wall_sprites(child, out)

func _setup_wall_views() -> void:
	for map in [modern_map, future_map]:
		if map == null:
			continue
		var arr: Array = []
		_collect_wall_sprites(map, arr)
		_wall_views[map] = arr

## 每帧：把当前时空的墙按等距深度分成「人在墙前 / 人在墙后」，
## 挡在人物前面的墙半透明化，这样角色永远不会被墙完全盖住。
## 每帧：把当前时空的墙按等距深度分成「人在墙前 / 人在墙后」，
## 挡住玩家**或敌人**的墙都会半透明化，角色永远不会被墙完全盖住。
func _update_wall_occlusion(delta: float) -> void:
	var map: Node2D = _map_of(Timeline.is_future())
	var arr: Array = _wall_views.get(map, [])
	if arr.is_empty():
		return
	var ppos: Vector2 = player.global_position
	var fade_speed: float = minf(1.0, delta * 14.0)
	# 需要"不被墙挡住"的目标：玩家 + 当前时空启用的生物（敌人 / 测试桩）
	var actors: Array = []
	actors.append({"pos": ppos, "rect": Rect2(ppos - Vector2(13.0, 54.0), Vector2(26.0, 58.0))})
	for n in _entities_modern + _entities_future + [ysort.get_node_or_null("FutureBoss"), _boss_transform_actor]:
		if n == null or not is_instance_valid(n) or not (n is Node2D):
			continue
		var nd: Node2D = n
		if not nd.visible or not nd.is_visible_in_tree():
			continue
		var ap: Vector2 = nd.global_position
		actors.append({"pos": ap, "rect": Rect2(ap - Vector2(16.0, 76.0), Vector2(32.0, 80.0))})
	for w in arr:
		var sp: Sprite2D = w["sp"]
		if not sp.visible:
			continue
		var base_y: float = w["base_y"]
		var in_front: bool = base_y > ppos.y
		sp.z_index = 2 if in_front else -2
		# 只有真的挡住"某个角色"才虚化：墙体矩形和身体矩形相交才算
		var wall_rect := Rect2(sp.global_position, w["size"])
		var covers := false
		if in_front:
			for a in actors:
				if base_y > (a["pos"] as Vector2).y and wall_rect.intersects(a["rect"] as Rect2):
					covers = true
					break
		var target: float = 0.35 if covers else 1.0
		sp.modulate.a = lerpf(sp.modulate.a, target, fade_speed)

## 旧的矩形边界墙（两个时空现在都靠空气墙，留着给调试/兜底）
func _set_walls_enabled(enabled: bool) -> void:
	if walls == null:
		return
	for child in walls.get_children():
		if child is CollisionShape2D:
			child.disabled = not enabled
# ---------------- 两个时空的生物各自独立 ----------------
## 切换到某个时空时：另一时空的生物整组隐藏 + 停处理 + 关碰撞，
## 它们身上的血量/韧性/复活计时都各自保留（节点是两套独立实例）。
func _set_era_entities(future: bool) -> void:
	for n in _entities_modern:
		var active := not future
		if is_instance_valid(n) and n.name == "ModernBoss":
			active = active and (n.spawned or n._entering)
		_set_entity_active(n, active)
	for n in _entities_future:
		_set_entity_active(n, future)
	var boss: Node = get_node_or_null("YSort/FutureBoss")
	if boss != null:
		_set_entity_active(boss, future and boss._entered)
	_set_entity_active(_boss_transform_actor, future)

## 数组会保留已释放的引用，必须先校验有效性再访问节点。
func _set_entity_active(node, active: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.visible = active
	node.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	# 切走时把这一组还在飞的子弹清掉，避免切回来时冒出一堆"旧时空"的子弹
	if not active and node is Node2D:
		for child in node.get_children():
			if child.has_method("is_bullet"):
				child.queue_free()
	if node is CollisionObject2D:
		if not node.has_meta("era_collision"):
			node.set_meta("era_collision", Vector2i(node.collision_layer, node.collision_mask))
		var original: Vector2i = node.get_meta("era_collision")
		node.set_deferred("collision_layer", original.x if active else 0)
		node.set_deferred("collision_mask", original.y if active else 0)


## 现代 boss 被击败：奖励天赋点并掉落道具，拾取后才解锁技能。
func _on_modern_boss_defeated() -> void:
	if modern_boss_defeated:
		return
	modern_boss_defeated = true
	player.add_talent_points(2)
	var pickup: Area2D = load("res://scripts/claw_pickup.gd").new()
	pickup.name = "ClawPickup"
	pickup.position = ysort.get_node("ModernBoss").position
	ysort.add_child(pickup)
	hint_label.text = "钩爪已掉落：靠近拾取；Tab 分配天赋点"

func _on_claw_picked_up() -> void:
	hint_label.text = "钩爪已获得：按 %s 使用；Tab 分配天赋点" % Keybinds.key_text("claw")

func _process(delta: float) -> void:
	_update_wall_occlusion(delta)
	_check_modern_boss_entrance()
	_check_boss_entrance()
	# 流程：原时空消失（播变换音效）→ 中点真正切时空 → 倒放出现（播出现音效）
	if Input.is_action_just_pressed("switch_time") and not _rewinding and not settings.is_open():
		if not player.is_era_shifting() and not player.is_dead():
			player.start_era_shift()
	# 生命归零 → 先播倒地动画，动画播完才黑屏回溯
	if not _rewinding and player.is_dead() and not player.is_dying():
		player.start_death()
	if not debug_label.visible:
		return
	debug_label.text = "fps %d   朝向 %s   速度 %d   %s   生命 %d/%d   韧性 %d/%d   无敌 %s" % [
		Engine.get_frames_per_second(),
		player.facing,
		int(player.speed),
		player.state,
		int(ceil(player.hp)), int(player.hp_max),
		int(ceil(player.poise)), int(player.poise_max),
		"是" if player.is_invulnerable() else "否",
	]

# ---------------- 死亡回溯 ----------------
func _start_rewind() -> void:
	_rewinding = true
	# 冻结角色：不再跑物理，输入也无效
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	player.afterimage.set_active(false)
	rewind.play()

## 画面全黑时复位：玩家看不到角色从死亡点瞬移回出生点
func _on_settings_opened() -> void:
	# 面板会盖住 HUD，先把提示和调试文字藏起来，关掉再恢复
	hint_label.visible = false
	debug_label.visible = false

func _on_settings_closed() -> void:
	hint_label.visible = show_hint

func _on_rewind_covered() -> void:
	player.respawn(spawn_position)

func _on_rewind_finished() -> void:
	# 兜底：万一 covered 没发出（比如被中断），这里也保证复位
	if player.is_dead() or player.global_position.distance_to(spawn_position) > 0.5:
		player.respawn(spawn_position)
	player.set_physics_process(true)
	_rewinding = false

## 自动化截图：
##   godot --path godot res://scenes/world.tscn -- --shot=out.png [--press=move_right,dodge]
##                                                  [--hold=1.2] [--pos=140,-80] [--nohud]
##                                                  [--kill] [--press_at=4.8:dodge]
func _capture_if_requested() -> void:
	var shot_path := ""
	var hold := 1.0
	var presses: Array = []
	var press_at: Array = []      # [[秒, [动作...]], ...]，相对"开始等待"的时刻
	var pos := Vector2.INF
	var no_hud := false
	var kill_first := false
	var perfect_at := -1.0
	var block_hit_at := -1.0
	var perfect_block_at := -1.0
	var show_exhaust := false
	var attack_stage := 0
	var _stage_applied := false
	var open_settings := false
	var break_dummy := false
	var hurt_player_pending := false
	var hit_pot_pending := -1
	var laser_pending := false
	var kill_modern_pending := false
	var claw_demo_pending := false
	var transform_demo_pending := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.trim_prefix("--shot=")
		elif a.begins_with("--press_at="):
			var spec := a.trim_prefix("--press_at=")
			var idx := spec.find(":")
			if idx > 0:
				press_at.append([float(spec.substr(0, idx)), Array(spec.substr(idx + 1).split(","))])
		elif a.begins_with("--press="):
			presses = Array(a.trim_prefix("--press=").split(","))
		elif a.begins_with("--hold="):
			hold = float(a.trim_prefix("--hold="))
		elif a.begins_with("--pos="):
			var parts := a.trim_prefix("--pos=").split(",")
			if parts.size() == 2:
				pos = Vector2(float(parts[0]), float(parts[1]))
		elif a == "--nohud":
			no_hud = true
		elif a.begins_with("--attack_stage="):
			attack_stage = int(a.trim_prefix("--attack_stage="))
		elif a == "--jitter_log":
			_jitter_log = true
		elif a == "--debug_walls":
			_debug_walls = true
			queue_redraw()
		elif a.begins_with("--enemy_pos="):
			var eparts: PackedStringArray = a.substr(12).split(",")
			if eparts.size() == 2:
				var en: Node = ysort.get_node_or_null("FutureEnemy")
				if en is Node2D:
					(en as Node2D).global_position = Vector2(float(eparts[0]), float(eparts[1]))
		elif a == "--print_walls":
			var wmap: Node2D = _map_of(Timeline.is_future())
			var warr: Array = _wall_views.get(wmap, [])
			for wi in range(mini(8, warr.size())):
				var wd: Dictionary = warr[wi]
				print("[wall] #%d cx=%.1f base_y=%.1f size=%s" % [wi, wd["cx"], wd["base_y"], str(wd["size"])])
		elif a == "--laser_demo":
			laser_pending = true
		elif a == "--claw_demo":
			player.has_claw = true
			claw_demo_pending = true
		elif a == "--kill_modern":
			kill_modern_pending = true
		elif a == "--transform_demo":
			transform_demo_pending = true
		elif a == "--boss_entrance":
			_start_future_boss_transform()
		elif a.begins_with("--hit_pot="):
			hit_pot_pending = int(a.split("=")[1])
		elif a.begins_with("--break_pot="):
			mark_pot_broken(int(a.split("=")[1]))
		elif a == "--hurt_player":
			hurt_player_pending = true
		elif a == "--break_enemy":
			var be: Node = ysort.get_node_or_null("ModernEnemy")
			if be != null and be.has_method("damage_poise"):
				be.damage_poise(999.0)
		elif a == "--enemy_kill":
			var ek: Node = ysort.get_node_or_null("FutureEnemy")
			if ek != null and ek.has_method("take_damage"):
				ek.take_damage(999.0)
		elif a == "--exhaust":
			show_exhaust = true
		elif a == "--break_dummy":
			break_dummy = true
		elif a == "--open_settings":
			open_settings = true
		elif a == "--kill":
			kill_first = true
		elif a.begins_with("--block_hit_at="):
			block_hit_at = float(a.trim_prefix("--block_hit_at="))
		elif a.begins_with("--perfect_block_at="):
			perfect_block_at = float(a.trim_prefix("--perfect_block_at="))
		elif a.begins_with("--perfect_at="):
			perfect_at = float(a.trim_prefix("--perfect_at="))
	if shot_path.is_empty():
		return

	if no_hud:
		debug_label.visible = false
		hint_label.visible = false
	if pos != Vector2.INF:
		player.global_position = pos
		# 让相机立刻对齐，避免平滑过程把角色拍在画面边缘
		var cam: Camera2D = player.get_node("Camera")
		cam.reset_smoothing()

	await get_tree().create_timer(0.4).timeout
	if show_exhaust:
		player.poise = 0.0
		player._start_exhaust()
	if break_dummy:
		var d: Node = ysort.get_node_or_null("TestDummy")
		if d != null:
			d.set_physics_process(true)
			d.take_damage(d.hp_max + 1.0)
	if open_settings:
		settings.open()
		await get_tree().create_timer(0.2).timeout
	for p in presses:
		Input.action_press(p)
	if kill_first:
		player.kill()   # 触发死亡回溯，用来截「时间回溯」画面

	# 等到 hold 秒；期间按 press_at 计划按下指定动作（用于卡时机截图）
	var t0 := Time.get_ticks_msec()
	# 完美格挡会暂停整棵树；截图模式下世界自己要保持运行，否则截图计时会卡住
	process_mode = Node.PROCESS_MODE_ALWAYS
	var pending := press_at.duplicate(true)
	var pressed_scheduled: Array = []
	while float(Time.get_ticks_msec() - t0) / 1000.0 < hold:
		var elapsed := float(Time.get_ticks_msec() - t0) / 1000.0
		# 截图用：攻击已经开始后，把连击切到指定段（--attack_stage=2/3）
		if attack_stage > 1 and not _stage_applied and player.state == "attack":
			player.combo_step = attack_stage
			player._begin_attack_stage()
			_stage_applied = true
		if perfect_block_at >= 0.0 and elapsed >= perfect_block_at and player.state == "block" and player.block_phase == "in":
			player.try_take_hit(10.0, player.global_position + Vector2(40, 0))
			perfect_block_at = -1.0
		if block_hit_at >= 0.0 and elapsed >= block_hit_at and player.is_blocking():
			player.try_take_hit(10.0, player.global_position + Vector2(40, 0))
			block_hit_at = -1.0
		if perfect_at >= 0.0 and elapsed >= perfect_at and player.state == "dodge" and not player.perfect_used:
			player.try_take_hit(10.0, Vector2.RIGHT)
			perfect_at = -1.0
		if _jitter_log:
			var cam2: Camera2D = get_viewport().get_camera_2d()
			if cam2 != null:
				var cc: Vector2 = cam2.get_screen_center_position()
				var ct: Transform2D = get_viewport().get_canvas_transform()
				var pin: Vector2 = player.get_global_transform_interpolated().origin
				var tile_sp: Sprite2D = _first_tile_of(modern_map)
				var tile_f := Vector2.ZERO
				if tile_sp != null:
					tile_f = tile_sp.get_global_transform_with_canvas().origin
				print("[jit] %d %.4f %.4f %.4f %.4f %.4f" % [Time.get_ticks_usec(), ct.origin.x, ct.origin.y, tile_f.x, tile_f.y, cc.y])
		if claw_demo_pending and elapsed >= hold - 0.45:
			claw_demo_pending = false
			player.claw_cooldown_left = 0.0
			player._fire_claw()
		if kill_modern_pending and elapsed >= hold - 2.2:
			kill_modern_pending = false
			for e in _entities_modern:
				if is_instance_valid(e) and "dead" in e and e.name != "ModernBoss":
					e.dead = true
		if transform_demo_pending and elapsed >= hold - 3.2:
			transform_demo_pending = false
			_start_future_boss_transform()
		if laser_pending and elapsed >= hold - 0.42:
			laser_pending = false
			var py: Node = ysort.get_node_or_null("EnergyPylon1")
			if py != null:
				py.activated = true
				py._try_attack()
		if hit_pot_pending >= 0 and elapsed >= hold - 0.45:
			var pot_hit: Node = ysort.get_node_or_null("FlowerPot%d" % (hit_pot_pending + 1))
			hit_pot_pending = -1
			if pot_hit != null and pot_hit.has_method("take_damage"):
				pot_hit.take_damage(10.0)
		if hurt_player_pending and elapsed >= hold - 0.15:
			hurt_player_pending = false
			player.hurt_invuln_left = 0.0
			player.try_take_hit(2.0, player.global_position + Vector2(40, 0))
		for item in pending.duplicate():
			if elapsed >= float(item[0]):
				for act in item[1]:
					Input.action_press(act)
					pressed_scheduled.append(act)
				pending.erase(item)
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(shot_path)
	print("[capture] player=(%.1f, %.1f) era=%d" % [player.global_position.x, player.global_position.y, Timeline.era])
	print("[capture] %s err=%d %dx%d" % [shot_path, err, img.get_width(), img.get_height()])

	await get_tree().create_timer(0.15).timeout
	get_tree().quit(0)

## 调试用：取地图里第一块地砖 Sprite2D
func _first_tile_of(map_node: Node2D) -> Sprite2D:
	if map_node == null:
		return null
	for c in map_node.get_children():
		if c is Sprite2D and String((c as Node).get_meta("meowa_kind", "tile")) == "tile":
			return c
		var r := _first_tile_of(c)
		if r != null:
			return r
	return null
