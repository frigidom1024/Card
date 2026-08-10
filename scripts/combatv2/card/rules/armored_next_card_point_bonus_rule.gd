class_name ArmoredNextCardPointBonusRule
extends CardRule


@export_range(1, 999, 1) var bonus_points: int = 1


func execute_on_card_added(context: CardChainRuleContext) -> bool:
	if context == null:
		return false
	if not context.is_added_card_next_to_source() or not context.added_card_has_armor():
		return false
	return context.add_points_to_added_card(bonus_points) > 0
