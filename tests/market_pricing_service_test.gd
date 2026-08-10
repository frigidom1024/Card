extends SceneTree

const MarketPriceContextScript = preload("res://scripts/game/market/market_price_context.gd")
const MarketPricingServiceScript = preload("res://scripts/game/market/market_pricing_service.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_prices_follow_card_rarity_and_reclaim_half()
	quit(1 if _failure_count > 0 else 0)


func _test_prices_follow_card_rarity_and_reclaim_half() -> void:
	var service: Object = MarketPricingServiceScript.new()
	var context: Object = MarketPriceContextScript.new()
	var expected_prices := {
		CardData.Rarity.COMMON: 2,
		CardData.Rarity.RARE: 4,
		CardData.Rarity.EPIC: 8,
		CardData.Rarity.LEGENDARY: 16,
	}
	for rarity in expected_prices:
		var card := CardData.new()
		card.rarity = rarity
		card.value = 999
		var expected_price: int = expected_prices[rarity]
		_expect(
			service.call("get_purchase_price", card, context) == expected_price,
			"rarity %d purchase price is %d" % [rarity, expected_price]
		)
		_expect(
			service.call("get_reclaim_price", card, context) == expected_price / 2,
			"rarity %d reclaim price is half the purchase price" % rarity
		)
	_expect(service.call("get_purchase_price", null, context) == 1, "null card price remains safe")
	_expect(service.call("get_reclaim_price", null, context) == 1, "null card reclaim price remains safe")
	_expect(service.call("get_refresh_cost", context) == 1, "refresh costs one gold")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)