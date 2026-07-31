class_name CardCondition
extends Resource

enum Comparison { EQUAL, GREATER_THAN, GREATER_OR_EQUAL, LESS_THAN, LESS_OR_EQUAL }


func evaluate(_context: CardResolutionContext) -> bool:
	return false


static func compare_values(actual: float, expected: float, comparison: Comparison) -> bool:
	match comparison:
		Comparison.EQUAL:
			return is_equal_approx(actual, expected)
		Comparison.GREATER_THAN:
			return actual > expected
		Comparison.GREATER_OR_EQUAL:
			return actual >= expected
		Comparison.LESS_THAN:
			return actual < expected
		Comparison.LESS_OR_EQUAL:
			return actual <= expected
	return false
