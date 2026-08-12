class_name CombatStartPointBonusRule
extends CardRule


@export_range(1, 999, 1) var bonus_points: int = 2


## Grants this card combat-only points through the common effect pipeline.
## CombatService2 removes the remaining temporary amount at encounter end.
func on_combat_started(draft:CombatEffectDraft) -> bool:
	if draft == null or draft.current_card == null or bonus_points <= 0:
		return false
	draft.add_card_points(
		bonus_points,
		draft.current_card,
		-1,
		"",
		{"temporary": true, "duration": "combat"},
		["combat_start", "temporary_card_points"]
	)
	return true
