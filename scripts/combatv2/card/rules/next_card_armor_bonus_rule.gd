class_name NextCardArmorBonusRule
extends CardRule


@export_range(1, 999, 1) var armor: int = 1


func execute_on_card_added(context: CardChainRuleContext) -> bool:
	if context == null or not context.is_added_card_next_to_source():
		return false
	return context.add_armor_to_added_card(armor) > 0
