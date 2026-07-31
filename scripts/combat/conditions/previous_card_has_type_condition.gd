class_name PreviousCardHasTypeCondition
extends CardCondition

@export var required_type: CardData.CardType = CardData.CardType.NORMAL


func evaluate(context: CardResolutionContext) -> bool:
	if context == null:
		return false
	var previous_card := context.get_previous_resolved_card()
	return (
		previous_card != null
		and previous_card.card_data != null
		and previous_card.card_data.card_type == required_type
	)
