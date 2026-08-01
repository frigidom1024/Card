class_name ShopItemData
extends Resource

const CardDataScript = preload("res://scripts/card/card_data.gd")

@export var card_data: CardDataScript
@export_range(0, 999, 1) var price: int = 0