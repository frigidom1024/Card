class_name PreviousDefenseHealBonusRule
extends CardRule


func on_attack(draft) -> bool:
	if draft == null:
		return false
	var previous: CardInstance = draft.get_previous_resolved_card()
	if previous == null or previous.card_data == null or previous.card_data.defense <= 0:
		return false
	draft.add_player_heal(1, ["previous_defense_heal_bonus"])
	return true
