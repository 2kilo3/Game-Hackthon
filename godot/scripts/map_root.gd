@tool
extends Node2D

@export_file("*.json") var meowa_map_json_path: String = "res://meowa-map.json"
@export var map_name: String = ""
@export var map_type: String = "topdown"
@export var map_width_tiles: int = 0
@export var map_height_tiles: int = 0
@export var tile_size: int = 0
@export var pixel_size: Vector2 = Vector2.ZERO

func get_tile_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	_find_nodes_with_kind(self, "tile", nodes)
	return nodes

func get_object_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	_find_nodes_with_kind(self, "object", nodes)
	return nodes

func _find_nodes_with_kind(root: Node, kind: String, nodes: Array[Node]) -> void:
	for child in root.get_children():
		if child.get_meta("meowa_kind", "") == kind:
			nodes.append(child)
		_find_nodes_with_kind(child, kind, nodes)
