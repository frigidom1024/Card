class_name AddHealOperation
extends CardOperation

@export var amount: int = 0


func apply(_context: CardResolutionContext, draft: CardResolutionDraft) -> void:
	if draft != null:
		draft.heal = maxi(draft.heal + amount, 0)
