extends RefCounted
class_name CardInstance

var card_data:CardData

@export var scene:PackedScene
enum ZONE
{
	DRAW,
	HAND,
	BOARD,
	DISCARD,
	DRAGLAYER
}

var cur_zone:ZONE

var battlefield_pos := Vector2i(-1,-1)
var direction:int = 0

func _init(card_data:CardData):
	card_data=card_data
