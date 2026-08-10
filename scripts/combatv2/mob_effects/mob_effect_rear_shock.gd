class_name MobEffectRearShock
extends "res://scripts/combatv2/mob_effect.gd"

@export_range(1, 99, 1) var damage: int = 1
@export_range(1, 99, 1) var card_count: int = 1

func on_attack(draft) -> bool:
	if draft == null or damage <= 0:
		return false
	var added := 0
	for card in draft.get_cards_behind_current(card_count):
		draft.add_damage(
			CombatEffect.Target.CARD,
			damage,
			CombatEffect.SourceType.MONSTER_EFFECT,
			_effect_source_name(draft),
			card,
			{},
			["rear_shock"]
		)
		added += 1
	return added > 0

func _effect_source_name(draft) -> String:
	return effect_name if not effect_name.is_empty() else "后排冲击"

