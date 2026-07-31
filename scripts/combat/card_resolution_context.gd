class_name CardResolutionContext
extends RefCounted

var _current_card: CardInstance
var _previous_resolved_card: CardInstance
var _resolved_cards: Array[CardInstance] = []
var _remaining_cards: Array[CardInstance] = []
var _current_index: int
var _total_card_count: int
var _player_max_hp: int
var _player_hp: int
var _player_defense: int
var _monster_max_hp: int
var _monster_hp: int
var _monster_defense: int
var _active_chain_rule_ids: Array[StringName] = []
var _current_batch_id: int
var _current_batch_card_count: int


func _init(state: CombatState, current_card: CardInstance, current_index: int) -> void:
	_current_card = _copy_card(current_card)
	_current_index = maxi(current_index, 0)
	if state == null:
		return
	_total_card_count = state.cards.size()
	_previous_resolved_card = _copy_card(
		state.resolved_cards.back() if not state.resolved_cards.is_empty() else null
	)
	for card in state.resolved_cards:
		_resolved_cards.append(_copy_card(card))
	for card in state.remaining_cards:
		_remaining_cards.append(_copy_card(card))
	for rule in state.active_chain_rules:
		if rule != null:
			_active_chain_rule_ids.append(rule.rule_id)
	_current_batch_id = state.current_batch_id
	_current_batch_card_count = state.current_batch_card_count
	if state.player_stats != null:
		_player_max_hp = state.player_stats.max_hp
		_player_hp = state.player_stats.hp
		_player_defense = state.player_stats.defense
	if state.monster != null and state.monster.stats != null:
		_monster_max_hp = state.monster.stats.max_hp
		_monster_hp = state.monster.stats.hp
		_monster_defense = state.monster.stats.defense


func get_current_card() -> CardInstance:
	return _copy_card(_current_card)


func get_previous_resolved_card() -> CardInstance:
	return _copy_card(_previous_resolved_card)


func get_resolved_cards() -> Array[CardInstance]:
	return _copy_cards(_resolved_cards)


func get_remaining_cards() -> Array[CardInstance]:
	return _copy_cards(_remaining_cards)


func get_current_index() -> int:
	return _current_index


func get_total_card_count() -> int:
	return _total_card_count


func get_player_max_hp() -> int:
	return _player_max_hp


func get_player_hp() -> int:
	return _player_hp


func get_player_defense() -> int:
	return _player_defense


func get_player_hp_ratio() -> float:
	return float(_player_hp) / float(_player_max_hp) if _player_max_hp > 0 else 0.0


func get_monster_max_hp() -> int:
	return _monster_max_hp


func get_monster_hp() -> int:
	return _monster_hp


func get_monster_defense() -> int:
	return _monster_defense


func get_monster_hp_ratio() -> float:
	return float(_monster_hp) / float(_monster_max_hp) if _monster_max_hp > 0 else 0.0


func get_active_chain_rule_ids() -> Array[StringName]:
	return _active_chain_rule_ids.duplicate()


func get_current_batch_id() -> int:
	return _current_batch_id


func get_current_batch_card_count() -> int:
	return _current_batch_card_count


func is_first_card() -> bool:
	return _total_card_count > 0 and _current_index == 0


func is_last_card() -> bool:
	return _total_card_count > 0 and _current_index == _total_card_count - 1


static func _copy_cards(cards: Array[CardInstance]) -> Array[CardInstance]:
	var copies: Array[CardInstance] = []
	for card in cards:
		copies.append(_copy_card(card))
	return copies


static func _copy_card(card: CardInstance) -> CardInstance:
	if card == null:
		return null
	var data_copy: CardData = null
	if card.card_data != null:
		data_copy = card.card_data.duplicate(true) as CardData
	var copy := CardInstance.new(data_copy)
	copy.cur_zone = card.cur_zone
	copy.battlefield_pos = card.battlefield_pos
	copy.direction = card.direction
	return copy
