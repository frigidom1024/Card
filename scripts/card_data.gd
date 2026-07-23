class_name CardData
extends Resource
@export var card_id: int = 0
@export var card_name: String = ""

func _init(p_card_id: int = 0, p_card_name: String = "") -> void:
	card_id = p_card_id
	card_name = p_card_name
