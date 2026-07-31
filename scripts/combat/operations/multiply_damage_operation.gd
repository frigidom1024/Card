class_name MultiplyDamageOperation
extends CardOperation

@export var multiplier: float = 1.0


func apply(_context: CardResolutionContext, draft: CardResolutionDraft) -> void:
	if draft != null:
		draft.damage = maxi(roundi(float(draft.damage) * multiplier), 0)
