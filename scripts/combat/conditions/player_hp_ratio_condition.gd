class_name PlayerHpRatioCondition
extends CardCondition

@export_range(0.0, 1.0, 0.01) var threshold: float = 0.5
@export var comparison: CardCondition.Comparison = CardCondition.Comparison.LESS_THAN


func evaluate(context: CardResolutionContext) -> bool:
	if context == null:
		return false
	return compare_values(context.get_player_hp_ratio(), clampf(threshold, 0.0, 1.0), comparison)
