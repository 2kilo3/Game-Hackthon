extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)
func frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame
func _run() -> void:
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await frames(2)
	var timeline = root.get_node("Timeline")
	for enemy in world._entities_modern + world._entities_future:
		enemy.dead = true
	world.modern_boss_defeated = true
	timeline.set_era(1)
	await frames(2)
	var boss = world.get_node("YSort/FutureBoss")
	check(world._boss_transform_running and is_instance_valid(world._boss_transform_actor), "normal gameplay starts modern-form entrance and transformation")
	boss.begin_entrance()
	await frames(2)
	timeline.set_era(0)
	await frames(2)
	var before: Vector2 = boss.position
	check(not boss.visible, "future boss hidden in Modern")
	check(boss.process_mode == Node.PROCESS_MODE_DISABLED, "future boss disabled in Modern")
	check(boss.collision_layer == 0 and boss.collision_mask == 0, "future boss collision disabled in Modern")
	world.player.position += Vector2(60, 0)
	await frames(20)
	check(boss.position == before, "moving player in Modern does not move future boss")
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	await create_timer(0.15).timeout
	print("BOSS_ERA_REPRO ", JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
