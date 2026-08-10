class_name PreviousWeaponDamageDoubleRule
extends CardRule


func on_attack(draft) -> bool:
	if draft == null:
		return false
	var previous: CardInstance = draft.get_previous_resolved_card()
	if previous == null or previous.card_data == null or not previous.card_data.tags.has(CardData.CardTag.WEAPON):
		return false
	var effect: CombatEffect = draft.get_monster_damage_effect()
	if effect == null or effect.cancelled:
		return false
	effect.value *= 2
	effect.add_tag("previous_weapon_damage_double")
	return true
