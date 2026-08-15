extends SceneTree

const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")
const MarketPricingServiceScript = preload("res://scripts/game/market/market_pricing_service.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_shop_uses_ribwood_card_library_and_binds_initial_products()
	await _test_shop_purchase_via_drag_preserves_exact_instance_and_restocks()
	await _test_shop_purchase_is_rejected_when_gold_is_insufficient()
	await _test_reclaim_via_drag_unregisters_exact_instance_and_pays_value()
	await _test_refresh_shop_charges_gold_and_replaces_products()
	quit(1 if _failure_count > 0 else 0)


func _test_shop_uses_ribwood_card_library_and_binds_initial_products() -> void:
	var manager = await _create_manager()
	if manager == null:
		return

	_expect(
		manager.card_library.resource_path == "res://data/levels/ribwood/card_lib.tres",
		"Shop uses the Ribwood card library"
	)
	var offers: Array[CardInstance] = manager.shop.get_offers()
	_expect(
		offers.size() == manager.shop.shop_zone.max_products,
		"Shop fills every product slot during run initialization"
	)
	for slot_index in range(manager.shop.shop_zone.max_products):
		var offer: CardInstance = manager.shop.get_offer(slot_index)
		var product: Card = manager.shop.shop_zone.get_product(slot_index)
		_expect(
			offer != null
			and offer.card_data != null
			and offer.card_data.resource_path.begins_with(
				"res://data/levels/ribwood/cards/"
			),
			"Shop offer %d comes from the Ribwood card set" % slot_index
		)
		_expect(
			product != null and product.get_card_inst() == offer,
			"Shop product %d binds its exact offer instance" % slot_index
		)
		_expect(
			product != null and product.drag_layer == manager.drag_layer,
			"Shop product %d binds the page drag layer" % slot_index
		)
	await _free_manager(manager)


func _test_shop_purchase_via_drag_preserves_exact_instance_and_restocks() -> void:
	var manager = await _create_manager()
	if manager == null:
		return

	var product: Card = manager.shop.shop_zone.get_product(0)
	var exact_inst: CardInstance = manager.shop.get_offer(0)
	if product == null or exact_inst == null or exact_inst.card_data == null:
		_expect(false, "Configured Shop supplies a product for purchase coverage")
		await _free_manager(manager)
		return

	var price := _purchase_price(manager, exact_inst.card_data)
	var gold_before: int = manager.player_data.gold
	var hand_count_before: int = manager.hand_zone.get_card_count()
	var cards_before: int = manager.cards_inst.size()
	var entities_before: int = manager.card_entities.size()
	var committed: bool = _drag_card_to(
		manager,
		product,
		manager.hand_zone.get_global_rect().get_center()
	)
	await process_frame

	_expect(committed, "Dragging an affordable Shop product into HandZone commits")
	_expect(
		manager.player_data.gold == gold_before - price,
		"Successful Shop purchase charges the purchase price"
	)
	_expect(
		(manager.game_info.get_node("GoldNumber") as Label).text
		== str(gold_before - price),
		"Successful Shop purchase publishes the new gold balance to GameInfo"
	)
	_expect(
		manager.hand_zone.get_card_count() == hand_count_before + 1,
		"Successful Shop purchase adds one Card to HandZone"
	)
	_expect(
		manager.cards_inst.size() == cards_before + 1,
		"Successful Shop purchase updates the public runtime instance collection"
	)
	_expect(
		manager.card_entities.size() == entities_before + 1,
		"Successful Shop purchase updates the public runtime Card collection"
	)
	_expect(
		manager.hand_zone.owns_card(product),
		"Purchased product becomes a stable HandZone member"
	)
	_expect(
		product.get_card_inst() == exact_inst,
		"Purchased Card preserves the exact offered CardInstance"
	)
	_expect(
		exact_inst in manager.cards_inst and product in manager.card_entities,
		"Purchased exact Card/CardInstance pair is tracked by GameManager"
	)

	var replacement_inst: CardInstance = manager.shop.get_offer(0)
	var replacement_card: Card = manager.shop.shop_zone.get_product(0)
	_expect(
		replacement_inst != null and replacement_inst != exact_inst,
		"Purchased slot receives a new replacement CardInstance"
	)
	_expect(
		replacement_card != null
		and replacement_card != product
		and replacement_card.get_card_inst() == replacement_inst,
		"Purchased slot receives a Card bound to the replacement instance"
	)
	_expect(
		replacement_card != null and replacement_card.drag_layer == manager.drag_layer,
		"Replacement product binds the page drag layer"
	)
	await _free_manager(manager)


func _test_shop_purchase_is_rejected_when_gold_is_insufficient() -> void:
	var manager = await _create_manager()
	if manager == null:
		return

	var product: Card = manager.shop.shop_zone.get_product(0)
	var exact_inst: CardInstance = manager.shop.get_offer(0)
	if product == null or exact_inst == null or exact_inst.card_data == null:
		_expect(false, "Configured Shop supplies a product for insufficient-gold coverage")
		await _free_manager(manager)
		return

	var price := _purchase_price(manager, exact_inst.card_data)
	manager.player_data.gold = maxi(price - 1, 0)
	var gold_before: int = manager.player_data.gold
	var hand_count_before: int = manager.hand_zone.get_card_count()
	var cards_before: int = manager.cards_inst.size()
	var entities_before: int = manager.card_entities.size()
	var committed: bool = _drag_card_to(
		manager,
		product,
		manager.hand_zone.get_global_rect().get_center()
	)
	await process_frame

	_expect(not committed, "Shop product drag is rejected before commit when gold is insufficient")
	_expect(
		manager.player_data.gold == gold_before,
		"Insufficient-gold purchase does not change player gold"
	)
	_expect(
		manager.hand_zone.get_card_count() == hand_count_before,
		"Insufficient-gold purchase does not add a hand Card"
	)
	_expect(
		manager.cards_inst.size() == cards_before
		and manager.card_entities.size() == entities_before,
		"Insufficient-gold purchase does not change runtime card tracking"
	)
	_expect(
		manager.shop.get_offer(0) == exact_inst,
		"Insufficient-gold purchase preserves the exact offer instance"
	)
	_expect(
		manager.shop.shop_zone.get_product(0) == product
		and product.get_card_inst() == exact_inst,
		"Insufficient-gold purchase preserves the exact Shop product"
	)
	_expect(
		manager.shop.shop_zone.owns_card(product),
		"Rejected Shop product remains owned by ShopZone"
	)
	await _free_manager(manager)


func _test_reclaim_via_drag_unregisters_exact_instance_and_pays_value() -> void:
	var manager = await _create_manager()
	if manager == null:
		return

	var hand_cards: Array[Card] = manager.hand_zone.get_cards()
	var card: Card = hand_cards[0] if not hand_cards.is_empty() else null
	var exact_inst: CardInstance = card.get_card_inst() if card != null else null
	var reclaimed_card_id := card.get_instance_id() if card != null else 0
	if card == null or exact_inst == null or exact_inst.card_data == null:
		_expect(false, "Configured run supplies a hand Card for reclaim coverage")
		await _free_manager(manager)
		return

	var card_value: int = exact_inst.card_data.value
	var reclaim_price := _reclaim_price(manager, exact_inst.card_data)
	var gold_before: int = manager.player_data.gold
	var hand_count_before: int = manager.hand_zone.get_card_count()
	var cards_before: int = manager.cards_inst.size()
	var entities_before: int = manager.card_entities.size()
	var committed: bool = _drag_card_to(
		manager,
		card,
		manager.reclaim_zone.get_global_rect().get_center()
	)
	var was_restored_to_hand: bool = manager.hand_zone.owns_card(card)
	await process_frame

	_expect(committed, "Dragging a tracked hand Card into ReclaimZone commits")
	_expect(
		manager.player_data.gold == gold_before + reclaim_price,
		"Reclaiming a Card grants its reclaim price in gold"
	)
	_expect(
		(manager.game_info.get_node("GoldNumber") as Label).text
		== str(gold_before + reclaim_price),
		"Reclaiming publishes the new gold balance to GameInfo"
	)
	_expect(
		manager.hand_zone.get_card_count() == hand_count_before - 1,
		"Reclaiming a Card removes it from HandZone"
	)
	_expect(
		manager.cards_inst.size() == cards_before - 1,
		"Reclaiming a Card updates the public runtime instance collection"
	)
	_expect(
		manager.card_entities.size() == entities_before - 1,
		"Reclaiming a Card updates the public runtime Card collection"
	)
	var reclaimed_card_still_tracked := false
	for tracked_card: Card in manager.card_entities:
		if (
			is_instance_valid(tracked_card)
			and tracked_card.get_instance_id() == reclaimed_card_id
		):
			reclaimed_card_still_tracked = true
			break
	_expect(
		exact_inst not in manager.cards_inst and not reclaimed_card_still_tracked,
		"Reclaimed exact Card/CardInstance pair is no longer tracked"
	)
	_expect(not was_restored_to_hand, "Reclaimed Card is not restored to HandZone")
	_expect(not is_instance_valid(card), "Reclaimed Card is freed after the transaction")
	_expect(
		exact_inst.cur_zone == CardInstance.ZONE.DISCARD
		and exact_inst.battlefield_pos == Vector2i(-1, -1)
		and exact_inst.direction == 0,
		"Reclaimed CardInstance is normalized to discard state"
	)
	_expect(
		reclaim_price == maxi(1, floori(float(card_value) * 0.5)),
		"Reclaim price defaults to half of the base card value"
	)
	await _free_manager(manager)


func _test_refresh_shop_charges_gold_and_replaces_products() -> void:
	var manager = await _create_manager()
	if manager == null:
		return

	var previous_offers: Array[CardInstance] = manager.shop.get_offers()
	var previous_products: Array[Card] = manager.shop.shop_zone.get_products()
	var gold_before: int = manager.player_data.gold
	var refreshed: bool = manager.shop.refresh_shop()
	await process_frame

	_expect(refreshed, "Configured Shop refresh succeeds when the player can pay")
	_expect(manager.player_data.gold == gold_before - 1, "Shop refresh charges one gold")
	_expect(
		(manager.game_info.get_node("GoldNumber") as Label).text == str(gold_before - 1),
		"Shop refresh publishes the new gold balance to GameInfo"
	)
	_expect(
		manager.shop.get_offers().size() == manager.shop.shop_zone.max_products,
		"Shop refresh repopulates every offer slot"
	)
	for slot_index in range(manager.shop.shop_zone.max_products):
		var offer: CardInstance = manager.shop.get_offer(slot_index)
		var product: Card = manager.shop.shop_zone.get_product(slot_index)
		_expect(
			offer != null and offer not in previous_offers,
			"Shop refresh creates a new CardInstance for slot %d" % slot_index
		)
		_expect(
			product != null
			and product not in previous_products
			and product.get_card_inst() == offer,
			"Shop refresh creates a new Card bound to slot %d offer" % slot_index
		)
		_expect(
			product != null and product.drag_layer == manager.drag_layer,
			"Refreshed product %d binds the page drag layer" % slot_index
		)
	await _free_manager(manager)


func _create_manager():
	var manager = GameManagerScene.instantiate()
	_expect(manager.configure_run(RevivalDeck), "Valid starter deck configures Shop integration run")
	root.add_child(manager)
	await process_frame
	_expect(
		manager.shop != null
		and manager.shop.shop_zone != null
		and manager.shop.get_offers().size() == manager.shop.shop_zone.max_products,
		"Configured run initializes the resident Shop and ShopZone"
	)
	return manager


func _free_manager(manager) -> void:
	if manager != null and is_instance_valid(manager):
		manager.queue_free()
		await process_frame


func _drag_card_to(manager, card: Card, destination: Vector2) -> bool:
	if not manager.drag_layer.start_drag(card):
		return false
	card.global_position = destination - card.size * 0.5
	return manager.drag_layer.end_drag(card)


func _purchase_price(manager, card_data: CardData) -> int:
	var pricing = MarketPricingServiceScript.new()
	var price_context := MarketPriceContext.new()
	price_context.player = manager.player_data
	price_context.market_state = manager.shop
	return pricing.get_purchase_price(card_data, price_context)


func _reclaim_price(manager, card_data: CardData) -> int:
	var pricing = MarketPricingServiceScript.new()
	var price_context := MarketPriceContext.new()
	price_context.player = manager.player_data
	price_context.market_state = manager.shop
	return pricing.get_reclaim_price(card_data, price_context)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
