extends SceneTree

const MarketPriceContextScript = preload("res://scripts/game/market/market_price_context.gd")
const MarketPricingServiceScript = preload("res://scripts/game/market/market_pricing_service.gd")
const PersistentMarketScene = preload("res://scenes/game/persistent_market.tscn")
const PersistentMarketStateScript = preload("res://scripts/game/market/persistent_market_state.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var market: Object = PersistentMarketScene.instantiate()
	root.add_child(market)
	await process_frame
	market.call("configure", _state_with_three_cards(), _player(), MarketPricingServiceScript.new())
	await process_frame

	_expect(market.get_node_or_null("OfferRow/OfferSlot1/CardPreview") is CardEntity, "first offer uses CardEntity")
	_expect(market.get_node_or_null("OfferRow/OfferSlot2/CardPreview") is CardEntity, "second offer uses CardEntity")
	_expect(market.get_node_or_null("OfferRow/OfferSlot3/CardPreview") is CardEntity, "third offer uses CardEntity")
	var preview := market.get_node("OfferRow/OfferSlot1/CardPreview") as CardEntity
	var first_slot := market.get_node("OfferRow/OfferSlot1") as Control
	_expect(market.custom_minimum_size == Vector2(584, 470), "market reserves a wide card-sized offer area")
	_expect(first_slot.size.x == 180.0, "each offer slot reserves full-size card width")
	_expect(preview.scale == Vector2.ONE, "market offer cards keep the standard gameplay card scale")
	_expect(preview.is_market_offer(), "offer preview starts as draggable market card")
	_expect(preview.input_pickable, "offer preview allows hover and right-click zoom")
	_expect((market.get_node("HeaderRow/RefreshCostLabel") as Label).text == "1 GOLD", "refresh cost uses pricing service")
	_expect((market.get_node("OfferRow/OfferSlot1/PriceLabel") as Label).text.ends_with("GOLD"), "offer exposes a gold price")
	_expect(market.call("is_over_reclaim_target", (market.get_node("ReclaimArea") as Control).get_global_rect().get_center()), "reclaim target accepts its center point")

	market.queue_free()
	await process_frame
	quit(1 if _failure_count > 0 else 0)


func _state_with_three_cards() -> Object:
	var library := CardLibrary.new()
	library.cards = [_card("A", 6), _card("B", 7), _card("C", 8)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var state: Object = PersistentMarketStateScript.new()
	state.call("initialize", library, rng)
	return state


func _player() -> PlayerData:
	var player := PlayerData.new()
	player.gold = 10
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
