class_name ChainLengthHeadArmorBonusRule
extends CardRule


@export_range(2, 999, 1) var minimum_chain_size: int = 4
@export_range(1, 999, 1) var armor: int = 1


func execute_on_card_added(context: CardChainRuleContext) -> bool:
	if context == null:
		return false
	if not context.is_added_card_head() or context.get_chain_size() < minimum_chain_size:
		return false
	return context.add_armor_to_added_card(armor) > 0
