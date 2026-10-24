extends Area2D
## 现代 Boss 掉落：靠近拾取，一次性解锁本局钩爪。

const HOOK_TEXTURE = preload("res://assets/claw/throw/E/throw_E_01.png")
var collected := false

func _ready() -> void:
	add_to_group("claw_pickup")
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	shape.position.y = -7
	add_child(shape)
	var icon := Sprite2D.new()
	icon.texture = HOOK_TEXTURE
	icon.region_enabled = true
	icon.region_rect = Rect2(HOOK_TEXTURE.get_image().get_used_rect())
	icon.position.y = -16
	icon.scale = Vector2(2, 2)
	add_child(icon)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if collected or not body.has_method("unlock_claw") or body.is_dead():
		return
	collected = true
	body.unlock_claw()
	hide()
	set_deferred("monitoring", false)
	queue_free()

func _draw() -> void:
	draw_circle(Vector2(0, -7), 18, Color(0.1, 0.7, 0.9, 0.2))
	draw_arc(Vector2(0, -7), 18, 0, TAU, 32, Color(0.5, 0.9, 1), 1.5, true)
	draw_string(ThemeDB.fallback_font, Vector2(-10, -29), "钩爪", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)
