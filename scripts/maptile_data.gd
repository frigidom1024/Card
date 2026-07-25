class_name MapTileData
extends Resource


enum Terrain {
	GRASS,
	FOREST,
	MOUNTAIN
}


var position: Vector2i
var terrain: Terrain
var event_type: String = ""


func _init(pos: Vector2i, type: Terrain):
	position = pos
	terrain = type
