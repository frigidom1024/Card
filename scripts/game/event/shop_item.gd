class_name ShopItem
extends RefCounted

var card_data: CardData
var price: int
var sold: bool = false


static func create(card: CardData, cost: int) -> ShopItem:
	var item = ShopItem.new()
	item.card_data = card
	item.price = cost
	return item
