extends SceneTree

const RunCardServicePath := "res://scripts/game/run/run_card_service.gd"
const CardManagerScript = preload("res://scripts/game/card_manager.gd")
const HandScene = preload("res://scenes/game/hand.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_starting_deck_cards_are_owned_and_added_to_hand()
	await _test_granted_card_is_tracked_only_after_it_enters_hand()
	await _test_existing_card_can_return_to_a_full_hand_without_duplication()
	await _test_existing_card_can_return_with_temporary_overflow()
	await _test_new_card_can_grant_with_temporary_overflow()
	await _test_reclaimed_card_is_forgotten_without_being_freed()
	quit(1 if _failure_count > 0 else 0)


func _test_starting_deck_cards_are_owned_and_added_to_hand() -> void:
	var service: Variant = _create_service()
	if service == null:
		return
	var result: bool = service.initialize_starting_deck(RevivalDeck)
	_expect(result, "runtime card service accepts a valid starting deck")
	_expect(
		service.get_instances().size() == RevivalDeck.starter_cards.size(),
		"runtime card service tracks every starter instance"
	)
	_expect(
		service.get_entities().size() == RevivalDeck.starter_cards.size(),
		"runtime card service tracks every starter entity"
	)

	for index in range(RevivalDeck.starter_cards.size()):
		var entity: CardEntity = service.get_entities()[index]
		_expect(
			service.get_instances()[index].card_data == RevivalDeck.starter_cards[index],
			"runtime card service preserves starter card order at index %d" % index
		)
		_expect(
			entity in service.hand_area.cards,
			"runtime card service places starter card %d in hand" % index
		)
		_expect(
			entity.drag_layer == service.drag_layer,
			"runtime card service assigns drag layer to starter card %d" % index
		)

	await _free_service_fixture(service)


func _test_granted_card_is_tracked_only_after_it_enters_hand() -> void:
	var service: Variant = _create_service()
	if service == null:
		return
	var card_data: CardData = RevivalDeck.starter_cards[0]
	service.hand_area.max_hand_size = 0
	_expect(
		not service.grant_to_hand(card_data),
		"runtime card service rejects reward card when hand is full"
	)
	_expect(service.get_instances().is_empty(), "failed reward grant does not retain an instance")
	_expect(service.get_entities().is_empty(), "failed reward grant does not retain an entity")

	service.hand_area.max_hand_size = 1
	_expect(
		service.grant_to_hand(card_data), "runtime card service grants card when hand has space"
	)
	_expect(service.get_instances().size() == 1, "successful reward grant tracks its instance")
	_expect(
		service.get_instances()[0].cur_zone == CardInstance.ZONE.HAND,
		"successful reward grant marks its instance as in hand"
	)
	_expect(
		service.get_entities()[0] in service.hand_area.cards,
		"successful reward grant adds its entity to hand"
	)

	await _free_service_fixture(service)


func _test_existing_card_can_return_to_a_full_hand_without_duplication() -> void:
	var service: Variant = _create_service()
	if service == null:
		return
	_expect(
		service.initialize_starting_deck(RevivalDeck),
		"fixture starter deck initializes before guide return"
	)
	var existing_count: int = service.get_entities().size()
	service.hand_area.max_hand_size = service.hand_area.cards.size()
	var guide := CardEntityScene.instantiate() as CardEntity
	guide.bind_instance(CardInstance.new(RevivalDeck.starter_cards[0]))
	service.drag_layer.add_child(guide)

	_expect(
		service.return_existing_to_hand(guide, true),
		"runtime card service returns an existing guide card despite a full hand"
	)
	_expect(guide in service.hand_area.cards, "returned guide card enters hand")
	_expect(
		service.hand_area.max_hand_size >= service.hand_area.cards.size(),
		"guide return expands hand capacity only as needed"
	)
	_expect(
		service.get_entities().size() == existing_count,
		"returning an untracked guide card does not duplicate player ownership"
	)
	_expect(
		service.return_existing_to_hand(guide, true) == false,
		"runtime card service rejects returning a card already in hand"
	)

	await _free_service_fixture(service)


func _test_existing_card_can_return_with_temporary_overflow() -> void:
	var service: Variant = _create_service()
	if service == null:
		return
	_expect(
		service.initialize_starting_deck(RevivalDeck),
		"fixture starter deck initializes before temporary return"
	)
	var returned_card: CardEntity = service.get_entities()[0]
	_expect(
		service.hand_area.remove_card(returned_card),
		"fixture removes the owned tail card from hand before retreat"
	)
	service.hand_area.max_hand_size = service.hand_area.cards.size()
	var original_max_hand_size: int = service.hand_area.max_hand_size

	if not service.has_method("return_existing_to_hand_temporarily"):
		_expect(false, "runtime card service exposes a temporary-overflow return for retreat tails")
		await _free_service_fixture(service)
		return
	_expect(
		service.call("return_existing_to_hand_temporarily", returned_card),
		"runtime card service can return a retreat tail with temporary hand overflow"
	)
	_expect(returned_card in service.hand_area.cards, "temporarily returned tail card enters hand")
	_expect(
		service.hand_area.max_hand_size == original_max_hand_size,
		"temporary retreat overflow restores the previous hand capacity"
	)
	_expect(
		returned_card in service.get_entities(),
		"temporary return preserves existing entity ownership"
	)
	_expect(
		returned_card.card_instance in service.get_instances(),
		"temporary return preserves existing instance ownership"
	)

	await _free_service_fixture(service)


func _test_new_card_can_grant_with_temporary_overflow() -> void:
	var service: Variant = _create_service()
	if service == null:
		return
	_expect(
		service.initialize_starting_deck(RevivalDeck),
		"fixture starter deck initializes before reward overflow"
	)
	var existing_count: int = service.get_entities().size()
	service.hand_area.max_hand_size = service.hand_area.cards.size()
	var original_max_hand_size: int = service.hand_area.max_hand_size

	_expect(
		service.has_method("grant_to_hand_temporarily"),
		"runtime card service exposes an overflow-safe encounter reward grant"
	)
	if service.has_method("grant_to_hand_temporarily"):
		_expect(
			service.call("grant_to_hand_temporarily", RevivalDeck.starter_cards[0]),
			"reward grant accepts a card when the normal hand is full"
		)
		_expect(
			service.get_entities().size() == existing_count + 1, "reward grant owns the new card"
		)
		_expect(
			service.get_entities().back() in service.hand_area.cards,
			"reward grant keeps the new card in hand"
		)
		_expect(
			service.hand_area.max_hand_size == original_max_hand_size,
			"reward grant restores the configured hand limit"
		)

	await _free_service_fixture(service)


func _test_reclaimed_card_is_forgotten_without_being_freed() -> void:
	var service: Variant = _create_service()
	if service == null:
		return
	_expect(
		service.initialize_starting_deck(RevivalDeck),
		"fixture starter deck initializes before market reclaim"
	)
	var card: CardEntity = service.get_entities()[0]
	_expect(service.forget_card(card), "runtime card service forgets a tracked reclaimed card")
	_expect(
		card not in service.get_entities(),
		"forgotten reclaimed card no longer has entity ownership"
	)
	_expect(
		card.card_instance not in service.get_instances(),
		"forgotten reclaimed card no longer has instance ownership"
	)
	_expect(
		is_instance_valid(card),
		"runtime card service leaves reclaimed entity alive for DragLayer cleanup"
	)
	_expect(not service.forget_card(card), "runtime card service ignores an already-forgotten card")

	await _free_service_fixture(service)


func _create_service():
	var service_script = ResourceLoader.load(RunCardServicePath)
	if service_script == null:
		_expect(
			false,
			"runtime card service script exists so GameManager can delegate card lifecycle ownership"
		)
		return null
	var card_manager := CardManagerScript.new()
	card_manager.card_scene = CardEntityScene
	var hand := HandScene.instantiate() as HandArea
	root.add_child(hand)
	var drag_layer := Node2D.new()
	root.add_child(drag_layer)
	var service = service_script.new()
	_expect(
		service.configure(card_manager, hand, drag_layer),
		"runtime card service configures real card, hand, and drag dependencies"
	)
	return service


func _free_service_fixture(service) -> void:
	service.clear()
	if is_instance_valid(service.hand_area):
		service.hand_area.queue_free()
	if is_instance_valid(service.drag_layer):
		service.drag_layer.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
