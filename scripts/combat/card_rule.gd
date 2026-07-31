class_name CardRule
extends Resource

@export var condition: CardCondition
@export var operation: CardOperation


func apply(context: CardResolutionContext, draft: CardResolutionDraft) -> void:
	if operation != null and (condition == null or condition.evaluate(context)):
		operation.apply(context, draft)
