extends SceneTree

const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_new_run_starts_with_faith()
	await _test_manually_removing_a_board_card_spends_one_faith()
	await _test_faith_is_visible_and_system_tail_return_is_free()
	await _test_zero_faith_allows_manual_chain_removal_and_generates_an_encounter()
	await _test_reaching_zero_faith_spawns_a_random_monster()
	quit(0 if _failure_count == 0 else 1)


func _test_new_run_starts_with_faith() -> void:
	var manager := GameManagerScene.instantiate()
	_expect(manager.configure_run(RevivalDeck), "faith setup configures a starting deck")
	root.add_child(manager)
	await process_frame
	_expect(manager.player_data.get("faith") == 3, "runtime PlayerData stores a new run's three faith")
	_expect(manager.get("faith") == null, "GameManager does not keep a duplicate faith value")
	_cleanup_manager(manager)


func _test_manually_removing_a_board_card_spends_one_faith() -> void:
	var manager := await _make_game_manager()
	var board: Board = manager.board
	var root_card := _place_card(manager, Vector2i(0, 0), CardData.CardType.ROOT)
	var tail_card := _place_card(manager, Vector2i(2, 0), CardData.CardType.NORMAL)
	_expect(root_card != null and tail_card != null, "faith setup places a two-card chain")
	if tail_card != null:
		manager.drag_layer.on_card_drag_start(tail_card)
	_expect(manager.player_data.get("faith") == 2, "manual chain removal spends PlayerData faith")
	var faith_label := manager.find_child("FaithLabel", true, false) as Label
	_expect(faith_label != null and faith_label.text == "信仰：2", "faith HUD refreshes after manual chain removal")
	_cleanup_manager(manager)


func _test_faith_is_visible_and_system_tail_return_is_free() -> void:
	var manager := await _make_game_manager()
	var tail_card := _place_card(manager, Vector2i(0, 0), CardData.CardType.ROOT)
	var follower := _place_card(manager, Vector2i(2, 0), CardData.CardType.NORMAL)
	var faith_label := manager.find_child("FaithLabel", true, false) as Label
	_expect(faith_label != null and faith_label.text == "信仰：3", "faith HUD shows the current faith")
	manager._return_tail_card_to_hand()
	_expect(manager.player_data.get("faith") == 3, "system tail return does not spend PlayerData faith")
	_expect(tail_card in manager.board.cards and follower in manager.hand_area.cards, "system tail return keeps the root and returns only the tail")
	_cleanup_manager(manager)


func _test_zero_faith_allows_manual_chain_removal_and_generates_an_encounter() -> void:
	var manager := await _make_game_manager()
	var board: Board = manager.board
	_place_card(manager, Vector2i(0, 0), CardData.CardType.ROOT)
	var tail_card := _place_card(manager, Vector2i(2, 0), CardData.CardType.NORMAL)
	manager.player_data.faith = 0
	var events_before := board.events.size()
	_expect(manager.drag_layer.can_start_drag(tail_card), "zero faith still permits manually dismantling the chain")
	manager.drag_layer.on_card_drag_start(tail_card)
	await process_frame
	_expect(manager.player_data.faith == -1, "manual retraction at zero faith can create faith debt")
	_expect(tail_card not in board.cards, "manual retraction at zero faith removes the selected chain card")
	_expect(board.events.size() == events_before + 1, "manual retraction at zero faith adds one map encounter")
	_cleanup_manager(manager)


func _test_reaching_zero_faith_spawns_a_random_monster() -> void:
	var manager := await _make_game_manager()
	manager.player_data.faith = 1
	var board: Board = manager.board
	_expect(_place_card(manager, Vector2i(0, 0), CardData.CardType.ROOT) != null, "residual encounter setup places root")
	var tail_card := _place_card(manager, Vector2i(2, 0), CardData.CardType.NORMAL)
	var events_before := board.events.size()
	if tail_card != null:
		manager.drag_layer.on_card_drag_start(tail_card)
	await process_frame
	_expect(manager.player_data.faith == 0, "manual retraction reaches zero faith")
	_expect(board.events.size() == events_before + 1, "zero faith retraction adds one map encounter")
	if board.events.size() == events_before + 1:
		var spawned_event: EventInstance = board.events.back().event_instance
		_expect(spawned_event.get_event_type() == EventData.EventType.MONSTER, "faith consequence only creates a normal monster encounter")
	_cleanup_manager(manager)


func _make_game_manager() -> Node:
	var manager := GameManagerScene.instantiate()
	_expect(manager.configure_run(RevivalDeck), "faith setup configures a starting deck")
	root.add_child(manager)
	await process_frame
	for event_node in manager.board.events.duplicate():
		manager.board.remove_event(event_node)
	return manager


func _place_card(manager: Node, left_cell: Vector2i, card_type: CardData.CardType) -> CardEntity:
	var data := CardData.new()
	data.card_type = card_type
	var instance := CardInstance.new(data)
	var card := CardEntityScene.instantiate() as CardEntity
	card.bind_instance(instance)
	card.drag_layer = manager.drag_layer
	root.add_child(card)
	card.global_position = manager.board.to_global(_horizontal_card_center(manager.board, left_cell))
	card.rotation_degrees = 90.0
	manager.cards_inst.append(instance)
	manager.card_entities.append(card)
	_expect(manager.board.add_card(card), "faith test card is added to the Board")
	return card


func _horizontal_card_center(board: Board, left_cell: Vector2i) -> Vector2:
	var right_cell := left_cell + Vector2i.RIGHT
	return board.to_local((board.grid_to_world_center(left_cell) + board.grid_to_world_center(right_cell)) / 2.0)


func _cleanup_manager(manager: Node) -> void:
	if manager != null and is_instance_valid(manager):
		manager.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
