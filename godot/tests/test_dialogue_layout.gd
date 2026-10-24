extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var dialog = load("res://addons/bureau_dialogue/dialogue.tscn").instantiate()
	root.add_child(dialog)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var sizes := [Vector2i(720, 405), Vector2i(1280, 720), Vector2i(320, 240), Vector2i(390, 844), Vector2i(1024, 768)]
	for size in sizes:
		root.size = size
		await process_frame
		await process_frame
		dialog.open_dialogue([{"speaker": "特斯拉", "text": "长文本应自动换行并支持滚动，不覆盖下一句按钮。".repeat(24)}])
		await process_frame
		await process_frame
		var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
		var rect: Rect2 = dialog.panel.get_global_rect()
		check(viewport.encloses(rect), "panel inside viewport " + str(size))
		check(absf(rect.get_center().x - viewport.get_center().x) < 1.0, "panel centered " + str(size))
		check(absf(viewport.end.y - rect.end.y - 12) < 1.0, "panel bottom fixed " + str(size))
		check(rect.encloses(dialog.next_button.get_global_rect()), "next button reachable " + str(size))
		check(dialog.scroll.get_v_scroll_bar().max_value > dialog.scroll.size.y, "long text scrolls " + str(size))
		for i in 2:
			check(viewport.encloses(dialog.portraits[i].get_global_rect()), "portrait visible %d %s" % [i, size])
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--capture-dir="):
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("对话布局_%dx%d.png" % [size.x, size.y]))
		dialog.close_dialogue()
	dialog.free()
	print("DIALOGUE_LAYOUT_RESULT ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
