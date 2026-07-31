class_name IsLastCardCondition
extends CardCondition


func evaluate(context: CardResolutionContext) -> bool:
	return context != null and context.is_last_card()
