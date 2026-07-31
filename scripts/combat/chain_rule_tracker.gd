class_name ChainRuleTracker
extends RefCounted

var _active_rules: Array[ChainRule] = []
var _open_rule: ChainRule


func start(rules: Array[ChainRule]) -> void:
	_active_rules.clear()
	_open_rule = null
	var accepted_rule_ids: Dictionary = {}
	for rule in rules:
		if rule == null or accepted_rule_ids.has(rule.rule_id):
			continue
		accepted_rule_ids[rule.rule_id] = true
		rule.reset_batch()
		_active_rules.append(rule)


func begin_card(card: CardInstance) -> bool:
	if _open_rule == null:
		return false
	if _card_matches_rule(card, _open_rule):
		return false
	_close_open_batch()
	return true


func finish_card(card: CardInstance) -> bool:
	if _open_rule != null:
		if _card_matches_rule(card, _open_rule):
			_open_rule.remaining_matching_cards -= 1
			if _open_rule.remaining_matching_cards <= 0:
				_close_open_batch()
				return true
			return false
		return true

	var matching_rule := _find_matching_rule(card)
	if matching_rule == null:
		return true
	_open_rule = matching_rule
	_open_rule.is_batch_open = true
	_open_rule.remaining_matching_cards = _open_rule.matching_count - 1
	if _open_rule.remaining_matching_cards <= 0:
		_close_open_batch()
		return true
	return false


func flush_pending() -> bool:
	if _open_rule == null:
		return false
	_close_open_batch()
	return true


func _find_matching_rule(card: CardInstance) -> ChainRule:
	for rule in _active_rules:
		if _card_matches_rule(card, rule):
			return rule
	return null


func _card_matches_rule(card: CardInstance, rule: ChainRule) -> bool:
	return card != null and card.card_data != null and card.card_data.tags.has(rule.required_tag)


func _close_open_batch() -> void:
	_open_rule.reset_batch()
	_open_rule = null
