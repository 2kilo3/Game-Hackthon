extends SceneTree
## 时空实体数组会保留已经死亡并释放的节点引用。

func _initialize() -> void:
	var world: Node2D = load("res://scripts/world.gd").new()
	var removed := Node2D.new()
	var survivor := Node2D.new()
	survivor.visible = false
	survivor.process_mode = Node.PROCESS_MODE_DISABLED
	world._entities_future.append(removed)
	world._entities_future.append(survivor)
	removed.free()
	world._set_era_entities(true)
	var enabled: bool = survivor.visible and survivor.process_mode == Node.PROCESS_MODE_INHERIT
	world._set_era_entities(false)
	var disabled: bool = not survivor.visible and survivor.process_mode == Node.PROCESS_MODE_DISABLED
	world.free()
	survivor.free()
	print("ENTITY_GUARD_RESULT ", JSON.stringify({"checks": 2, "passed": enabled and disabled}))
	quit(0 if enabled and disabled else 1)
