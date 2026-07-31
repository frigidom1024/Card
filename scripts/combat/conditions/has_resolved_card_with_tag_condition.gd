class_name HasResolvedCardWithTagCondition
extends CardCondition

@export var required_tag: CardData.CardTag = CardData.CardTag.WEAPON


func evaluate(context: CardResolutionContext) -> bool:
	if context == null:
		return false
	for card in context.get_resolved_cards():
		if card != null and card.card_data != null and required_tag in card.card_data.tags:
			return true
	return false
