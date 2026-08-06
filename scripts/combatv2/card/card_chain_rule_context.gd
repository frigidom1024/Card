class_name CardChainRuleContext
extends RefCounted


var _chain: Array[CardInstance] = []
var _source_card: CardInstance
var _added_card: CardInstance
var _source_index: int = -1
var _added_index: int = -1


func _init(
	chain: Array[CardInstance], source_card: CardInstance, added_card: CardInstance
) -> void:
	_chain = chain.duplicate()
	_source_card = source_card
	_added_card = added_card
	_source_index = _chain.find(source_card)
	_added_index = _chain.find(added_card)


func get_source_card() -> CardInstance:
	return _source_card


func get_added_card() -> CardInstance:
	return _added_card


func get_source_index() -> int:
	return _source_index


func get_added_index() -> int:
	return _added_index


func get_chain_size() -> int:
	return _chain.size()


## "Next" always means one physical position toward the chain head.
func is_added_card_next_to_source() -> bool:
	return _source_index >= 0 and _added_index == _source_index + 1


func is_added_card_head() -> bool:
	return _added_index >= 0 and _added_index == _chain.size() - 1


func add_points_to_added_card(amount: int) -> int:
	if _added_card == null:
		return 0
	return _added_card.add_points(amount)


func add_armor_to_added_card(amount: int) -> int:
	if _added_card == null:
		return 0
	return _added_card.add_armor(amount)
