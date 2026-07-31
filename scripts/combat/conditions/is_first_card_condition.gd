class_name IsFirstCardCondition
extends CardCondition


func evaluate(context: CardResolutionContext) -> bool:
	return context != null and context.is_first_card()
