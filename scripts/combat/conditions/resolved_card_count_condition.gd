class_name ResolvedCardCountCondition
extends CardCondition

@export var expected_count: int = 0
@export var comparison: CardCondition.Comparison = CardCondition.Comparison.EQUAL


func evaluate(context: CardResolutionContext) -> bool:
	if context == null:
		return false
	return compare_values(
		float(context.get_resolved_cards().size()), float(expected_count), comparison
	)
