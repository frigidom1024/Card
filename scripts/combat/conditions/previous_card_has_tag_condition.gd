class_name PreviousCardHasTagCondition
extends CardCondition

@export var required_tag: CardData.CardTag = CardData.CardTag.WEAPON


func evaluate(context: CardResolutionContext) -> bool:
	if context == null:
		return false
	var previous_card := context.get_previous_resolved_card()
	return (
		previous_card != null
		and previous_card.card_data != null
		and required_tag in previous_card.card_data.tags
	)
