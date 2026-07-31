class_name CardResolutionDraft
extends RefCounted

var damage: int
var defense: int
var heal: int
var extra_effects: Array[CombatEffect] = []


static func from_card(card: CardData) -> CardResolutionDraft:
	var draft := CardResolutionDraft.new()
	if card == null:
		return draft
	draft.damage = maxi(card.damage, 0)
	draft.defense = maxi(card.defense, 0)
	draft.heal = maxi(card.heal, 0)
	return draft


func add_extra_effect(type: CombatEffect.Type, target: CombatEffect.Target, value: int) -> void:
	extra_effects.append(CombatEffect.new(type, target, value, CombatEffect.SourceType.SYSTEM))


func to_effects(source_type: CombatEffect.SourceType, source_name: String) -> Array[CombatEffect]:
	var effects: Array[CombatEffect] = []
	if damage > 0:
		effects.append(
			CombatEffect.new(
				CombatEffect.Type.DAMAGE,
				CombatEffect.Target.MONSTER,
				damage,
				source_type,
				source_name
			)
		)
	if defense > 0:
		effects.append(
			CombatEffect.new(
				CombatEffect.Type.ADD_DEFENSE,
				CombatEffect.Target.PLAYER,
				defense,
				source_type,
				source_name
			)
		)
	if heal > 0:
		effects.append(
			CombatEffect.new(
				CombatEffect.Type.HEAL, CombatEffect.Target.PLAYER, heal, source_type, source_name
			)
		)
	for effect in extra_effects:
		if effect != null:
			effects.append(
				CombatEffect.new(effect.type, effect.target, effect.value, source_type, source_name)
			)
	return effects
