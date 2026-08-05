extends SceneTree

const CoordinatorPath := "res://scripts/game/market/persistent_market_coordinator.gd"
const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0
var _last_market_message := ""


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_purchase_restores_drag_offer_then_grants_runtime_card()
	await _test_reclaim_forgets_runtime_tracking_only_after_transaction_succeeds()
	quit(1 if _failure_count > 0 else 0)


func _test_purchase_restores_drag_offer_then_grants_runtime_card() -> void:
	var fixture := await _create_fixture()
	if fixture.is_empty():
		return
	var manager = fixture.manager
	var coordinator = fixture.coordinator
	var market = manager.persistent_market
	var offer: int = market.get_offer_slot_for_card(market.get_node("OfferRow/OfferSlot1/CardPreview"))
	var offer_card: CardEntity = market.get_node("OfferRow/OfferSlot1/CardPreview")
	var initial_entities: int = manager._run_card_service.get_entities().size()

	manager.drag_layer.on_card_drag_start(offer_card)
	coordinator.handle_purchase_requested(offer_card, offer)

	_expect(manager._run_card_service.get_entities().size() == initial_entities + 1, "purchase grants one tracked runtime card")
	_expect(offer_card.get_parent() == market.get_node("OfferRow/OfferSlot1"), "purchase restores the dragged offer preview before ending the flow")
	_expect(_last_market_message == "CARD PURCHASED", "purchase reports its existing success message")
	await _free_manager(manager)


func _test_reclaim_forgets_runtime_tracking_only_after_transaction_succeeds() -> void:
	var fixture := await _create_fixture()
	if fixture.is_empty():
		return
	var manager = fixture.manager
	var coordinator = fixture.coordinator
	var owned_card: CardEntity = manager._run_card_service.get_entities().back()

	manager.drag_layer.on_card_drag_start(owned_card)
	coordinator.handle_reclaim_requested(owned_card)

	_expect(owned_card not in manager._run_card_service.get_entities(), "successful reclaim removes only runtime ownership tracking")
	_expect(is_instance_valid(owned_card), "market coordinator leaves freeing the dragged visual card to DragLayer")
	_expect(_last_market_message.begins_with("CARD RECLAIMED · +"), "reclaim reports its existing payout message")
	await _free_manager(manager)


func _create_fixture() -> Dictionary:
	_last_market_message = ""
	var coordinator_script = ResourceLoader.load(CoordinatorPath)
	_expect(coordinator_script != null, "persistent market coordinator script exists")
	if coordinator_script == null:
		return {}
	var manager = GameManagerScene.instantiate()
	_expect(manager.configure_run(RevivalDeck), "fixture configures a valid run")
	root.add_child(manager)
	await process_frame
	var coordinator = coordinator_script.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_expect(
		coordinator.configure(
			manager.persistent_market,
			manager.card_manager.card_lib,
			manager.player_data,
			manager.hand_area,
			manager._run_card_service,
			MarketPricingService.new(),
			rng
		),
		"market coordinator accepts run market dependencies"
	)
	coordinator.connect_drag_layer(manager.drag_layer, manager.hand_tray)
	coordinator.market_message_changed.connect(_on_market_message)
	return {"manager": manager, "coordinator": coordinator}


func _on_market_message(text: String, _is_error: bool) -> void:
	_last_market_message = text


func _free_manager(manager) -> void:
	if manager != null and is_instance_valid(manager):
		manager.queue_free()
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)