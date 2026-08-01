extends RefCounted
class_name CardInstance

@export var card_data:CardData = null

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

func _init(data:CardData):
	card_data = data

# ========== 调试专用：生成默认测试卡牌 ==========
static func create_debug_card() -> CardInstance:
	var data = load("res://data/cards/AllThingsRevival.tres") as CardData
	return CardInstance.new(data)
