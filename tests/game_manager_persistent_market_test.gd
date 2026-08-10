extends SceneTree

const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")
const MarketPricingServiceScript = preload("res://scripts/game/market/market_pricing_service.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_market_purchase_via_drag_adds_card_and_charges_value()
	await _test_market_purchase_restores_offer_when_gold_is_insufficient()
	await _test_market_purchase_restores_offer_when_hand_is_full()
	await _test_market_reclaim_via_drag_removes_card_and_pays_half_value()
	await _test_refresh_button_charges_gold_and_repopulates_offers()
	await _test_market_uses_ribwood_card_library()
	quit(1 if _failure_count > 0 else 0)


func _test_market_uses_ribwood_card_library() -> void:
	var manager = await _create_manager()
	if manager == null:
		return

	_expect(
		manager.card_manager.card_lib.resource_path == "res://data/levels/ribwood/card_lib.tres",
		"persistent market uses the Ribwood card library"
	)
	for card_data in manager._persistent_market_coordinator.get_state().offers:
		_expect(
			card_data != null and card_data.resource_path.begins_with("res://data/levels/ribwood/cards/"),
			"persistent market offer comes from the Ribwood card set"
		)
	await _free_manager(manager)


func _test_market_purchase_via_drag_adds_card_and_charges_value() -> void:
	var manager = await _create_manager()
	if manager == null:
		return

	var market = manager.persistent_market
	var offer_card := _offer_card(market, 0)
	var offered_data: CardData = manager._persistent_market_coordinator.get_state().get_offer(0)
	var price := _purchase_price(manager, offered_data)
	var gold_before: int = manager.player_data.gold
	var hand_count_before: int = manager.hand_area.get_card_count()
	var cards_before: int = manager.cards_inst.size()

	_expect(offer_card != null and offer_card.is_market_offer(), "market offer is draggable in offer mode")
	if offer_card != null:
		_drag_card_to(manager, offer_card, manager.hand_tray.get_global_rect().get_center())
		await process_frame

	_expect(manager.player_data.gold == gold_before - price, "dragging an offer into the hand charges its card value")
	_expect(manager.hand_area.get_card_count() == hand_count_before + 1, "successful market purchase adds one card to the hand")
	_expect(manager.cards_inst.size() == cards_before + 1, "successful market purchase adds one runtime card instance")
	_expect(manager.card_entities.size() == cards_before + 1, "successful market purchase tracks one runtime card entity")
	_expect(offer_card != null and offer_card.get_parent() != manager.drag_layer, "successful purchase returns the offer preview to its market slot")
	var offer_slot := market.get_node("OfferRow/OfferSlot1") as Control
	_expect(offer_card != null and offer_card.get_parent() == offer_slot, "purchased slot keeps its preview under the slot")
	_expect(offer_card != null and offer_card.position == Vector2(90, 112), "purchased slot restores the card to its centered slot position")
	_expect(offer_card != null and offer_card.scale == Vector2.ONE, "purchased slot restores the standard card scale")
	_expect(manager._persistent_market_coordinator.get_state().get_offer(0) != null, "successful purchase replaces the consumed market offer")
	await _free_manager(manager)


func _test_market_purchase_restores_offer_when_gold_is_insufficient() -> void:
	var manager = await _create_manager()
	if manager == null:
		return

	var market = manager.persistent_market
	var offer_card := _offer_card(market, 0)
	var offered_data: CardData = manager._persistent_market_coordinator.get_state().get_offer(0)
	var price := _purchase_price(manager, offered_data)
	manager.player_data.gold = max(price - 1, 0)
	var gold_before: int = manager.player_data.gold
	var hand_count_before: int = manager.hand_area.get_card_count()
	var cards_before: int = manager.cards_inst.size()

	if offer_card != null:
		_drag_card_to(manager, offer_card, manager.hand_tray.get_global_rect().get_center())
		await process_frame

	_expect(manager.player_data.gold == gold_before, "insufficient-gold purchase does not change player gold")
	_expect(manager.hand_area.get_card_count() == hand_count_before, "insufficient-gold purchase does not add a hand card")
	_expect(manager.cards_inst.size() == cards_before, "insufficient-gold purchase does not create a card instance")
	_expect(manager._persistent_market_coordinator.get_state().get_offer(0) == offered_data, "insufficient-gold purchase preserves the market offer")
	_expect(offer_card != null and offer_card.get_parent() != manager.drag_layer, "insufficient-gold purchase restores the dragged offer preview")
	await _free_manager(manager)


func _test_market_purchase_restores_offer_when_hand_is_full() -> void:
	var manager = await _create_manager()
	if manager == null:
		return

	var market = manager.persistent_market
	var offer_card := _offer_card(market, 0)
	var offered_data: CardData = manager._persistent_market_coordinator.get_state().get_offer(0)
	var gold_before: int = manager.player_data.gold
	var hand_count_before: int = manager.hand_area.get_card_count()
	var cards_before: int = manager.cards_inst.size()
	var original_max_hand_size: int = manager.hand_area.max_hand_size
	manager.hand_area.max_hand_size = hand_count_before

	if offer_card != null:
		_drag_card_to(manager, offer_card, manager.hand_tray.get_global_rect().get_center())
		await process_frame

	_expect(manager.player_data.gold == gold_before, "full-hand purchase does not change player gold")
	_expect(manager.hand_area.get_card_count() == hand_count_before, "full-hand purchase does not add a hand card")
	_expect(manager.cards_inst.size() == cards_before, "full-hand purchase does not create a card instance")
	_expect(manager._persistent_market_coordinator.get_state().get_offer(0) == offered_data, "full-hand purchase preserves the market offer")
	_expect(offer_card != null and offer_card.get_parent() != manager.drag_layer, "full-hand purchase restores the dragged offer preview")
	manager.hand_area.max_hand_size = original_max_hand_size
	await _free_manager(manager)


func _test_market_reclaim_via_drag_removes_card_and_pays_half_value() -> void:
	var manager = await _create_manager()
	if manager == null:
		return

	var player_card: CardEntity = manager.card_entities[0] if not manager.card_entities.is_empty() else null
	if player_card == null or player_card.card_instance == null:
		_expect(false, "configured run supplies a player card for reclaim coverage")
		await _free_manager(manager)
		return

	var card_instance: CardInstance = player_card.card_instance
	var card_value: int = card_instance.card_data.value
	var reclaim_price := _reclaim_price(manager, card_instance.card_data)
	var gold_before: int = manager.player_data.gold
	var hand_count_before: int = manager.hand_area.get_card_count()
	var cards_before: int = manager.cards_inst.size()
	var entities_before: int = manager.card_entities.size()
	var reclaim_area := manager.persistent_market.get_node("ReclaimArea") as Control

	_drag_card_to(manager, player_card, reclaim_area.get_global_rect().get_center())
	var was_restored_to_hand: bool = player_card in manager.hand_area.cards
	await process_frame

	_expect(manager.player_data.gold == gold_before + reclaim_price, "reclaiming a card grants half its value in gold")
	_expect(manager.hand_area.get_card_count() == hand_count_before - 1, "reclaiming a card removes it from the hand")
	_expect(manager.cards_inst.size() == cards_before - 1, "reclaiming a card removes its runtime instance")
	_expect(manager.card_entities.size() == entities_before - 1, "reclaiming a card removes its runtime entity")
	_expect(card_instance not in manager.cards_inst, "reclaimed card instance is no longer tracked by the run")
	_expect(not was_restored_to_hand, "reclaimed card is not restored to the hand after drag completion")
	_expect(not is_instance_valid(player_card), "reclaimed card preview is freed after the reclaim transaction")
	_expect(reclaim_price == max(1, floori(float(card_value) * 0.5)), "reclaim price defaults to half of base card value")
	await _free_manager(manager)


func _test_refresh_button_charges_gold_and_repopulates_offers() -> void:
	var manager = await _create_manager()
	if manager == null:
		return

	var market = manager.persistent_market
	var refresh_button := market.get_node("HeaderRow/RefreshButton") as Button
	var refresh_cost := 1
	var gold_before: int = manager.player_data.gold
	manager._persistent_market_coordinator.get_state().offers.clear()
	market.refresh_display()

	refresh_button.emit_signal("pressed")
	await process_frame

	_expect(manager.player_data.gold == gold_before - refresh_cost, "refresh button deducts the market refresh gold cost")
	_expect(manager._persistent_market_coordinator.get_state().offers.size() == 3, "refresh button repopulates all three market offers")
	for slot_index in 3:
		var displayed_card := _offer_card(market, slot_index)
		_expect(manager._persistent_market_coordinator.get_state().get_offer(slot_index) != null, "refresh creates offer data for slot %d" % slot_index)
		_expect(
			displayed_card != null and displayed_card.card_instance != null and displayed_card.card_instance.card_data == manager._persistent_market_coordinator.get_state().get_offer(slot_index),
			"refresh updates the preview card for slot %d" % slot_index
		)
	await _free_manager(manager)


func _create_manager():
	var manager = GameManagerScene.instantiate()
	_expect(manager.configure_run(RevivalDeck), "valid starter deck configures persistent market test run")
	root.add_child(manager)
	await process_frame
	_expect(manager._persistent_market_coordinator != null and manager._persistent_market_coordinator.is_ready(), "configured run initializes the persistent market")
	return manager


func _free_manager(manager) -> void:
	if manager != null and is_instance_valid(manager):
		manager.queue_free()
		await process_frame


func _drag_card_to(manager, card: CardEntity, destination: Vector2) -> void:
	manager.drag_layer.on_card_drag_start(card)
	card.global_position = destination
	manager.drag_layer.on_card_drag_end(card)


func _offer_card(market, slot_index: int) -> CardEntity:
	return market.get_node_or_null("OfferRow/OfferSlot%d/CardPreview" % (slot_index + 1)) as CardEntity


func _purchase_price(manager, card_data: CardData) -> int:
	var context = MarketPricingServiceScript.new()
	var price_context = load("res://scripts/game/market/market_price_context.gd").new()
	price_context.player = manager.player_data
	price_context.market_state = manager._persistent_market_coordinator.get_state()
	return context.get_purchase_price(card_data, price_context)


func _reclaim_price(manager, card_data: CardData) -> int:
	var pricing = MarketPricingServiceScript.new()
	var price_context = load("res://scripts/game/market/market_price_context.gd").new()
	price_context.player = manager.player_data
	price_context.market_state = manager._persistent_market_coordinator.get_state()
	return pricing.get_reclaim_price(card_data, price_context)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)