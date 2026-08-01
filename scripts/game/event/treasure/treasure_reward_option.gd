class_name TreasureRewardOption
extends RefCounted

const CardDataScript = preload("res://scripts/card/card_data.gd")

enum Kind { CARD, GOLD }

var kind: Kind
var card_data: CardDataScript
var gold_amount := 0


static func card(card: CardDataScript):
	var option = TreasureRewardOption.new()
	option.kind = Kind.CARD
	option.card_data = card
	return option


static func gold(amount: int):
	var option = TreasureRewardOption.new()
	option.kind = Kind.GOLD
	option.gold_amount = amount
	return option