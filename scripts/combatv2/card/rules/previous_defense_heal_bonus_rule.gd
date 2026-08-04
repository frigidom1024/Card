class_name PreviousDefenseHealBonusRule
extends CardRule


func execute(context: CardResolutionContext, draft: CardResolutionDraft) -> CardResolutionDraft:
	if context == null or draft == null:
		return draft
	var previous_card := context.get_previous_resolved_card()
	if (
		previous_card != null
		and previous_card.card_data != null
		and previous_card.card_data.defense > 0
	):
		draft.heal += 1
	return draft
