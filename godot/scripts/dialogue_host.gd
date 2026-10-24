extends Node
## 可选模块接入；宿主负责暂停在完美格挡期间仍会处理的主角。

const MODULE := "res://addons/bureau_dialogue/dialogue.tscn"
const STORY = preload("story_dialogue.gd")
var dialogue: CanvasLayer
var _pending: Array[String] = []
var _seen := {}
var _current_story := ""
var _player_mode := Node.PROCESS_MODE_INHERIT
var _hint_visible := true
var _holding := false
var _ending := false
var _epilogue_visible := false
var _fade: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(MODULE):
		dialogue = load(MODULE).instantiate()
		add_child(dialogue)
		dialogue.opened.connect(_hold_player)
		dialogue.closed.connect(_restore_player)
		dialogue.closed.connect(_on_story_closed)
		dialogue.line_changed.connect(_on_line_changed)
		dialogue.tree_exiting.connect(_restore_player)
	get_parent().ready.connect(_connect_story_events)

func _connect_story_events() -> void:
	var world := get_parent()
	world.get_node("YSort/ModernBoss").defeated.connect(queue_story.bind("modern_boss_defeated"))
	world.get_node("YSort/ModernBoss").appeared.connect(queue_story.bind("modern_boss_appeared"))
	world.player.claw_unlocked.connect(_on_claw_picked_up)
	world.talents.closed.connect(_on_talents_closed)
	Timeline.era_changed.connect(_on_era_changed)
	world.future_boss_appeared.connect(queue_story.bind("future_boss_appeared"))
	world.get_node("YSort/FutureBoss").player_killed.connect(queue_story.bind("future_boss_first_death"))
	world.get_node("YSort/FutureBoss").died.connect(queue_story.bind("future_boss_defeated"))
	world.pot_destroyed.connect(queue_story.bind("pot_broken"))
	queue_story("prologue")

func queue_story(id: String) -> void:
	if _ending or not is_instance_valid(dialogue) or not STORY.LINES.has(id) or _seen.has(id):
		return
	_seen[id] = true
	_pending.append(id)

func _on_claw_picked_up() -> void:
	queue_story("claw_picked_up")
	_on_era_changed(Timeline.era)

func _on_talents_closed() -> void:
	if get_parent().player.has_claw:
		queue_story("talents_closed")

func _on_era_changed(_era: int) -> void:
	if Timeline.is_future() and get_parent().player.has_claw:
		queue_story("future_entered")

func _process(_delta: float) -> void:
	var world := get_parent()
	if _ending or _pending.is_empty() or is_open() or get_tree().paused or world._rewinding:
		return
	if world.player.is_dead() or world.player.is_era_shifting():
		return
	_current_story = _pending[0]
	if open_dialogue(STORY.lines_for(_current_story, world.pot_broken.has(true), Timeline.is_future())):
		_pending.pop_front()
	else:
		_current_story = ""

func open_dialogue(lines: Array, portraits: Dictionary = {}, names: Dictionary = {}) -> bool:
	if _ending or not is_instance_valid(dialogue):
		return false
	return dialogue.open_dialogue(lines, portraits, names)

func is_open() -> bool:
	return is_instance_valid(dialogue) and dialogue.is_open()

func _hold_player() -> void:
	if _holding:
		return
	var player := get_node("../YSort/Player")
	_player_mode = player.process_mode
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var hint := get_node("../HUD/Hint")
	_hint_visible = hint.visible
	hint.visible = false
	_holding = true

func _restore_player() -> void:
	if not _holding:
		return
	var player := get_node_or_null("../YSort/Player")
	if is_instance_valid(player):
		player.process_mode = _player_mode
	var hint := get_node_or_null("../HUD/Hint")
	if is_instance_valid(hint):
		hint.visible = _hint_visible
	_holding = false

func _on_line_changed(_speaker: String, text: String, _index: int) -> void:
	if _current_story == "future_boss_defeated":
		_epilogue_visible = text == "（未完待续）"

func _on_story_closed() -> void:
	var closed_story := _current_story
	_current_story = ""
	if closed_story == "prologue":
		queue_story("battle_start")
		if _pending.has("battle_start"):
			_pending.erase("battle_start")
			_pending.push_front("battle_start")
	elif closed_story == "future_boss_defeated":
		get_tree().paused = true
		_hold_player()
		if _epilogue_visible:
			_finish_game()
		else:
			# 跳过结尾时仍先展示“未完待续”，不恢复战斗。
			_show_epilogue.call_deferred()

func _show_epilogue() -> void:
	_current_story = "future_boss_defeated"
	open_dialogue([STORY.LINES.future_boss_defeated[-1]])

func _finish_game() -> void:
	if _ending:
		return
	_ending = true
	_pending.clear()
	Engine.time_scale = 1.0
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	layer.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade, "modulate:a", 1.0, 0.7)
	tween.tween_callback(_open_game_over)

func _open_game_over() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/game_over.tscn")
	if error != OK:
		push_error("游戏结束界面加载失败：" + error_string(error))

func _exit_tree() -> void:
	_restore_player()
