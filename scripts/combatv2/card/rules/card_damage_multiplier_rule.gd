class_name CardDamageMultiplierRule
extends "res://scripts/combatv2/card/card_rule.gd"

## Multiplies this card's point-clash damage by editing the outgoing effect.
@export_range(1, 99, 1) var multiplier: int = 2

func on_attack(draft) -> bool:
	if draft == null:
		return false
	var effect: CombatEffect = draft.get_monster_damage_effect()
	if effect == null or effect.cancelled:
		return false
	effect.value *= maxi(multiplier, 1)
	effect.add_tag("card_damage_multiplier")
	return true
