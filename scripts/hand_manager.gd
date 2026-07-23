extends HBoxContainer

@export var card_ui: PackedScene

var cards_on_hand: Array[CardData] = []
var _card_ui_nodes: Array[Control] = []


func add_card(card: CardData) -> void:
	cards_on_hand.append(card)
	var new_cardui = card_ui.instantiate()
	new_cardui.set_card_data(card)
	add_child(new_cardui)
	_card_ui_nodes.append(new_cardui)


func remove_card(card: CardData) -> void:
	var idx = cards_on_hand.find(card)
	if idx >= 0:
		cards_on_hand.remove_at(idx)
		var node = _card_ui_nodes[idx]
		_card_ui_nodes.remove_at(idx)
		node.queue_free()
	
