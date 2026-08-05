extends SceneTree

const MarketPriceContextScript = preload("res://scripts/game/market/market_price_context.gd")
const MarketPricingServiceScript = preload("res://scripts/game/market/market_pricing_service.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_prices_use_card_value_and_never_return_zero()
	quit(1 if _failure_count > 0 else 0)


func _test_prices_use_card_value_and_never_return_zero() -> void:
	var card := CardData.new()
	card.value = 7
	var service: Object = MarketPricingServiceScript.new()
	var context: Object = MarketPriceContextScript.new()
	_expect(service.call("get_purchase_price", card, context) == 7, "purchase uses card value")
	_expect(service.call("get_reclaim_price", card, context) == 3, "reclaim floors half value")
	_expect(service.call("get_refresh_cost", context) == 1, "refresh costs one gold")
	card.value = 0
	_expect(service.call("get_purchase_price", card, context) == 1, "purchase price clamps to one")
	_expect(service.call("get_reclaim_price", card, context) == 1, "reclaim price clamps to one")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)