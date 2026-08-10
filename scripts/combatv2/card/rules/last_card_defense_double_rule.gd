class_name LastCardDefenseDoubleRule
extends CardRule


func on_attack(draft) -> bool:
	if draft == null or not draft.is_current_card_last() or draft.current_card == null or draft.current_card.card_data == null:
		return false
	var defense := maxi(draft.current_card.card_data.defense, 0) * 2
	if defense <= 0:
		return false
	draft.add_player_defense(defense, ["last_card_defense_double"])
	return true
