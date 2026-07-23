class_name CardData

var card_id: int = 0
var card_name: String = ""

enum CardPos {
	DrawPile,
	HandArea,
	BattleField,
	DiscardPile
}

# pos表示卡牌左上角位置如果为（-1,-1）不在布阵区
# dir表示卡牌朝向，卡牌0，2表示竖直方向
var BattleField_pos:Vector2i
var BattleField_dir:int


func _init(p_card_id: int = 0, p_card_name: String = "") -> void:
	card_id = p_card_id
	card_name = p_card_name
