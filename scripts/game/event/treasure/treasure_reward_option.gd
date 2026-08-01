class_name TreasureRewardOption
extends RefCounted


enum Kind { CARD, GOLD }

var kind: Kind
var card_data: CardData
var gold_amount := 0


static func card(card: CardData):
	var option = TreasureRewardOption.new()
	option.kind = Kind.CARD
	option.card_data = card
	return option


static func gold(amount: int):
	var option = TreasureRewardOption.new()
	option.kind = Kind.GOLD
	option.gold_amount = amount
	return option