class_name WeaponComboRootRuleProvider
extends RootChainRuleProvider

@export var required_tag: CardData.CardTag = CardData.CardTag.WEAPON
@export var matching_count := 2


func build_rules(context: CardResolutionContext) -> Array[ChainRule]:
	var source_name := ""
	if context != null:
		var root_card := context.get_current_card()
		if root_card != null and root_card.card_data != null:
			source_name = root_card.card_data.card_name
	return [ChainRule.new(&"weapon_combo", required_tag, matching_count, source_name)]
