class_name PreviousDefenseDamageBonusRule
extends CardRule


func on_attack(draft) -> bool:
	if draft == null:
		return false
	var previous: CardInstance = draft.get_previous_resolved_card()
	if previous == null or previous.card_data == null or previous.card_data.defense <= 0:
		return false
	var effect: CombatEffect = draft.get_monster_damage_effect()
	if effect == null or effect.cancelled:
		return false
	effect.value += 2
	effect.add_tag("previous_defense_damage_bonus")
	return true
