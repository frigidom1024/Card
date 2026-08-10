class_name LastCardDefenseBonusRule
extends CardRule


func on_attack(draft) -> bool:
	if draft == null or not draft.is_current_card_last():
		return false
	draft.add_player_defense(2, ["last_card_defense"])
	return true
