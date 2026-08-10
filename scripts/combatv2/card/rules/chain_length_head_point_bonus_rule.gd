class_name ChainLengthHeadPointBonusRule
extends CardRule


@export_range(2, 999, 1) var minimum_chain_size: int = 4
@export_range(1, 999, 1) var bonus_points: int = 1


func execute_on_card_added(context: CardChainRuleContext) -> bool:
	if context == null:
		return false
	if not context.is_added_card_head() or context.get_chain_size() < minimum_chain_size:
		return false
	return context.add_points_to_added_card(bonus_points) > 0
