class_name AddDamageOperation
extends CardOperation

@export var amount: int = 0


func apply(_context: CardResolutionContext, draft: CardResolutionDraft) -> void:
	if draft != null:
		draft.damage = maxi(draft.damage + amount, 0)
