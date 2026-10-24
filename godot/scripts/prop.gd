extends StaticBody2D
## 场景道具（柱子 / 木箱）：贴图 + 脚底矩形碰撞。
##
## 原点放在脚底，方便参与父节点的 y-sort（y 越大越靠前，自然产生遮挡关系）。
## 在 world.tscn 里实例化后，用检查器改 texture / foot_width / foot_height 即可。
##
## 注意：texture 的 setter 会在节点还没 ready 时触发（场景加载顺序），
## 所以这里用 is_node_ready() 保护，ready 后再统一应用一次。

@export var texture: Texture2D:
	set(value):
		texture = value
		if is_node_ready():
			_apply()

## 碰撞宽度占贴图宽度的比例（0~1），太大容易“隔空卡住”
@export_range(0.1, 1.0, 0.05) var foot_width := 0.7
## 脚底碰撞高度（像素）
@export_range(4.0, 40.0, 1.0) var foot_height := 12.0

@onready var sprite: Sprite2D = $Sprite
@onready var shape_node: CollisionShape2D = $Shape

func _ready() -> void:
	_apply()

func _apply() -> void:
	if texture == null:
		return
	sprite.texture = texture
	# 贴图原点居中，把整张图往上移，让脚底落在节点原点
	sprite.offset = Vector2(0.0, -texture.get_height() / 2.0)
	var rect := shape_node.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
		shape_node.shape = rect
	rect.size = Vector2(texture.get_width() * foot_width, foot_height)
	shape_node.position = Vector2(0.0, -foot_height / 2.0)
