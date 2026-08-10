class_name BehindHeadPreTriggerRule
extends CardRule


## Positional condition for a one-time battle-opening strike.
func should_trigger_before_head(context: CardResolutionContext) -> bool:
	return context != null and context.is_directly_behind_head()


## The scout attacks before the normal head clash, but deliberately does not
## add the base monster retaliation effect. The effect pipeline still resolves
## the outgoing damage and records it for combat logs/animation playback.
func on_pre_combat(draft) -> bool:
	if draft == null or draft.current_card == null:
		return false
	var points: int = draft.current_card.current_points
	if points <= 0:
		return false
	draft.add_damage(
		CombatEffect.Target.MONSTER,
		points,
		draft.get_current_source_type(),
		draft.get_current_source_name(),
		null,
		{},
		["pre_combat", "card_attack", "no_retaliation"]
	)
	return true