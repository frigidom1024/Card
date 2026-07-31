class_name AddDefenseOperation
extends CardOperation

@export var amount: int = 0


func apply(_context: CardResolutionContext, draft: CardResolutionDraft) -> void:
	if draft != null:
		draft.defense = maxi(draft.defense + amount, 0)
