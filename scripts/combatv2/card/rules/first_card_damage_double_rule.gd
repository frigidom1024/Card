class_name FirstCardDamageDoubleRule
extends CardRule


func on_attack(draft) -> bool:
	if draft == null or not draft.is_current_card_first():
		return false
	var effect: CombatEffect = draft.get_monster_damage_effect()
	if effect == null or effect.cancelled:
		return false
	effect.value *= 2
	effect.add_tag("first_card_double")
	return true
