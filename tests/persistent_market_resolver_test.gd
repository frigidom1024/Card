extends SceneTree

const MarketPriceContextScript = preload("res://scripts/game/market/market_price_context.gd")
const MarketPricingServiceScript = preload("res://scripts/game/market/market_pricing_service.gd")
const PersistentMarketResolverScript = preload("res://scripts/game/market/persistent_market_resolver.gd")
const PersistentMarketStateScript = preload("res://scripts/game/market/persistent_market_state.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_purchase_deducts_gold_and_replaces_only_bought_slot()
	_test_rejected_purchase_preserves_gold_and_offers()
	_test_reclaim_credits_half_value()
	_test_refresh_costs_gold_and_rerolls_offers()
	quit(1 if _failure_count > 0 else 0)


func _test_purchase_deducts_gold_and_replaces_only_bought_slot() -> void:
	var state := _state_with_cards()
	var player := _player(20)
	var published_gold: Array[int] = []
	player.gold_changed.connect(func(value: int) -> void:
		published_gold.append(value)
	)
	var resolver: Object = PersistentMarketResolverScript.new(MarketPricingServiceScript.new())
	var context: Object = _context(player, state)
	var bought: CardData = state.call("get_offer", 1)
	var left = state.call("get_offer", 0)
	var right = state.call("get_offer", 2)
	var result: Object = resolver.call("purchase", state, 1, player, true, context)
	_expect(result.get("success"), "purchase succeeds with gold and hand capacity")
	_expect(result.get("card_data") == bought, "result returns purchased card")
	_expect(player.gold == 20 - 2, "purchase deducts the common rarity price")
	_expect(published_gold == [18], "purchase publishes the new gold balance")
	_expect(state.call("get_offer", 0) == left and state.call("get_offer", 2) == right, "purchase leaves other slots unchanged")


func _test_rejected_purchase_preserves_gold_and_offers() -> void:
	var state := _state_with_cards()
	var player := _player(0)
	var resolver: Object = PersistentMarketResolverScript.new(MarketPricingServiceScript.new())
	var context: Object = _context(player, state)
	var before_offers: Array = (state.get("offers") as Array).duplicate()
	var result: Object = resolver.call("purchase", state, 0, player, false, context)
	_expect(not result.get("success"), "full hand rejects purchase")
	_expect(player.gold == 0, "rejected purchase preserves gold")
	_expect(state.get("offers") == before_offers, "rejected purchase preserves offers")


func _test_reclaim_credits_half_value() -> void:
	var player := _player(0)
	var published_gold: Array[int] = []
	player.gold_changed.connect(func(value: int) -> void:
		published_gold.append(value)
	)
	var resolver: Object = PersistentMarketResolverScript.new(MarketPricingServiceScript.new())
	var card := _card("Sold Card", 7)
	var result: Object = resolver.call("reclaim", card, player, _context(player, null))
	_expect(result.get("success"), "reclaim accepts a card")
	_expect(result.get("gold_delta") == 1, "reclaim returns half the common rarity price")
	_expect(player.gold == 1, "reclaim credits player gold")
	_expect(published_gold == [1], "reclaim publishes the new gold balance")


func _test_refresh_costs_gold_and_rerolls_offers() -> void:
	var state := _state_with_cards()
	var player := _player(1)
	var published_gold: Array[int] = []
	player.gold_changed.connect(func(value: int) -> void:
		published_gold.append(value)
	)
	var resolver: Object = PersistentMarketResolverScript.new(MarketPricingServiceScript.new())
	var result: Object = resolver.call("refresh", state, player, _context(player, state))
	_expect(result.get("success"), "refresh succeeds with one gold")
	_expect(player.gold == 0, "refresh costs one gold")
	_expect(published_gold == [0], "refresh publishes the new gold balance")


func _state_with_cards() -> Object:
	var library := CardLibrary.new()
	library.cards = [_card("A", 6), _card("B", 7), _card("C", 8), _card("D", 9), _card("E", 10)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var state: Object = PersistentMarketStateScript.new()
	state.call("initialize", library, rng)
	return state


func _context(player: PlayerData, state) -> Object:
	var context: Object = MarketPriceContextScript.new()
	context.set("player", player)
	context.set("market_state", state)
	return context


func _player(gold: int) -> PlayerData:
	var player := PlayerData.new()
	player.gold = gold
	return player


func _card(card_name: String, value: int) -> CardData:
	var card := CardData.new()
	card.card_name = card_name
	card.value = value
	return card


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)