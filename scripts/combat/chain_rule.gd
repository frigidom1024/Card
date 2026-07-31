class_name ChainRule
extends RefCounted

var rule_id: StringName
var required_tag: CardData.CardTag
var matching_count: int
var remaining_matching_cards: int
var source_name: String
var is_batch_open := false


func _init(
	rule_id_value: StringName,
	required_tag_value: CardData.CardTag,
	matching_count_value: int,
	source_name_value: String
) -> void:
	rule_id = rule_id_value
	required_tag = required_tag_value
	matching_count = maxi(matching_count_value, 1)
	remaining_matching_cards = matching_count
	source_name = source_name_value


func reset_batch() -> void:
	remaining_matching_cards = matching_count
	is_batch_open = false
