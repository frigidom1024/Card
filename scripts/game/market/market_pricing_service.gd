class_name MarketPricingService
extends RefCounted


const RARITY_PRICES := {
	CardData.Rarity.COMMON: 2,
	CardData.Rarity.RARE: 4,
	CardData.Rarity.EPIC: 8,
	CardData.Rarity.LEGENDARY: 16,
}


func get_purchase_price(card_data: CardData, _context) -> int:
	if card_data == null:
		return 1
	return get_rarity_price(card_data.rarity)


func get_rarity_price(rarity: CardData.Rarity) -> int:
	return int(RARITY_PRICES.get(rarity, RARITY_PRICES[CardData.Rarity.COMMON]))


func get_reclaim_price(card_data: CardData, context) -> int:
	return maxi(1, floori(float(get_purchase_price(card_data, context)) * 0.5))


func get_refresh_cost(_context) -> int:
	return 1
