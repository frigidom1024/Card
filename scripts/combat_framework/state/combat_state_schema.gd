class_name CombatStateSchema
extends RefCounted

## 新战斗运行时使用稳定 ID 和普通 Dictionary，不保存 Node/Resource 引用。
static func create_initial_state(
	player: Dictionary,
	monster: Dictionary,
	cards: Dictionary,
	chain_card_ids: Array
) -> Dictionary:
	var normalized_cards: Dictionary = {}
	for raw_card_id in cards.keys():
		var card_id := str(raw_card_id)
		var card_data: Dictionary = cards.get(raw_card_id, {}) as Dictionary
		normalized_cards[card_id] = _normalize_card(card_id, card_data)
	return {
		"player": _normalize_actor(player, "player", false),
		"monster": _normalize_actor(monster, "monster", true),
		"cards": normalized_cards,
		"chain": {
			"card_ids": chain_card_ids.duplicate(),
		},
	}


static func _normalize_actor(data: Dictionary, fallback_id: String, include_attack: bool) -> Dictionary:
	var max_hp := maxi(int(data.get("max_hp", data.get("hp", 1))), 1)
	var hp := clampi(int(data.get("hp", max_hp)), 0, max_hp)
	var result := {
		"entity_id": str(data.get("entity_id", fallback_id)),
		"hp": hp,
		"max_hp": max_hp,
		"shield": maxi(int(data.get("shield", 0)), 0),
		"alive": hp > 0,
	}
	if include_attack:
		result["attack"] = maxi(int(data.get("attack", 0)), 0)
	else:
		result["gold"] = maxi(int(data.get("gold", 0)), 0)
	return result


static func _normalize_card(card_id: String, data: Dictionary) -> Dictionary:
	var max_points := maxi(int(data.get("max_points", data.get("points", 0))), 0)
	var points := maxi(int(data.get("points", max_points)), 0)
	return {
		"entity_id": card_id,
		"points": points,
		"max_points": max_points,
		"shield": maxi(int(data.get("shield", 0)), 0),
		"alive": points > 0,
	}
