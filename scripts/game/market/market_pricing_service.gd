class_name MarketPricingService
extends RefCounted


func get_purchase_price(card_data: CardData, _context) -> int:
	if card_data == null:
		return 1
	return maxi(1, card_data.value)


func get_reclaim_price(card_data: CardData, context) -> int:
	return maxi(1, floori(float(get_purchase_price(card_data, context)) * 0.5))


func get_refresh_cost(_context) -> int:
	return 1
