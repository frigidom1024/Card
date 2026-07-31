class_name AddCombatEffectOperation
extends CardOperation

@export var effect_type: CombatEffect.Type = CombatEffect.Type.DAMAGE
@export var target: CombatEffect.Target = CombatEffect.Target.MONSTER
@export var value: int = 0


func apply(_context: CardResolutionContext, draft: CardResolutionDraft) -> void:
	if draft != null:
		draft.add_extra_effect(effect_type, target, value)
