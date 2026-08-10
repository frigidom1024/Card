class_name MobEffectShieldBreak
extends "res://scripts/combatv2/mob_effect.gd"

@export_range(1.0, 10.0, 0.5) var armor_multiplier: float = 2.0

func on_attack(draft) -> bool:
	if draft == null:
		return false
	var effect: CombatEffect = draft.get_card_damage_effect()
	if effect == null:
		return false
	var current := float(effect.get_parameter("armor_multiplier", 1.0))
	effect.set_parameter("armor_multiplier", current * maxf(armor_multiplier, 0.0))
	effect.add_tag("shield_break")
	return true


