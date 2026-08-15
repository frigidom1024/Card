extends SceneTree

const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")
const CardScene = preload("res://scenes/card/card.tscn")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_new_run_keeps_faith_as_hidden_domain_state()
	await _test_confirmed_board_card_retraction_spends_gold_without_changing_faith()
	quit(0 if _failure_count == 0 else 1)


func _test_new_run_keeps_faith_as_hidden_domain_state() -> void:
	var manager := GameManagerScene.instantiate()
	_expect(manager.configure_run(RevivalDeck), "faith setup configures a starting deck")
	root.add_child(manager)
	await process_frame
	_expect(
		manager.player_data.get("faith") == PlayerData.INITIAL_FAITH,
		"runtime PlayerData retains the run-scoped faith domain value"
	)
	_expect(manager.get("faith") == null, "GameManager does not keep a duplicate faith value")
	_expect(
		manager.get_node_or_null("GameplayCanvas/Hud/GameInfo/FaithSeal") == null,
		"GameInfo only presents vitality and gold"
	)
	await _cleanup_manager(manager)


func _test_confirmed_board_card_retraction_spends_gold_without_changing_faith() -> void:
	var manager := await _make_game_manager()
	var root_card := _place_card(manager, Vector2i(0, 0), CardData.CardType.ROOT)
	var tail_card := _place_card(manager, Vector2i(2, 0), CardData.CardType.NORMAL)
	_expect(root_card != null and tail_card != null, "faith setup places a two-card chain")
	var faith_before: int = manager.player_data.faith
	var gold_before: int = manager.player_data.gold
	if tail_card != null:
		_expect(manager.drag_layer.start_drag(tail_card), "DraggerLayer starts the chain retraction")
		_move_card_center_to(tail_card, manager.hand_zone.get_global_rect().get_center())
		_expect(manager.drag_layer.end_drag(tail_card), "HandZone accepts the retracted card")
		await process_frame
	_expect(
		manager.player_data.faith == faith_before,
		"confirmed manual retraction leaves hidden faith domain state unchanged"
	)
	_expect(
		manager.player_data.gold == gold_before - CardRetractionCostService.COST_PER_RETURNED_CARD,
		"confirmed manual retraction spends gold"
	)
	_expect(
		root_card in manager.board.board_zone.get_cards()
		and tail_card not in manager.board.board_zone.get_cards()
		and tail_card in manager.hand_zone.get_cards(),
		"confirmed manual retraction moves only the selected tail card to HandZone"
	)
	var gold_number := manager.get_node_or_null("GameplayCanvas/Hud/GameInfo/GoldNumber") as Label
	_expect(
		gold_number != null and gold_number.text == str(manager.player_data.gold),
		"GameInfo refreshes the displayed gold after retraction cost"
	)
	await _cleanup_manager(manager)


func _make_game_manager() -> Node:
	var manager := GameManagerScene.instantiate()
	_expect(manager.configure_run(RevivalDeck), "faith setup configures a starting deck")
	root.add_child(manager)
	await process_frame
	for event_node in manager.board.event_zone.get_events().duplicate():
		manager.board.remove_event(event_node)
	return manager


func _place_card(manager: Node, left_cell: Vector2i, card_type: CardData.CardType) -> Card:
	var data := CardData.new()
	data.card_type = card_type
	data.max_points = 1
	var instance := CardInstance.new(data)
	var card := CardScene.instantiate() as Card
	card.bind_card_inst(instance)
	card.bind_drag_layer(manager.drag_layer)
	root.add_child(card)
	var card_service := manager.get_run_context().card_service as RunCardService
	if not card_service.register_existing_instance(instance, card):
		_expect(false, "faith test card registers in RunCardService")
		return card
	instance.direction = 1
	card.global_position = manager.board.to_global(
		_horizontal_card_center(manager.board, left_cell)
	) - card.size * 0.5
	card.target_position = card.position
	card.rotation_degrees = 90.0
	card.refresh_display()
	_expect(manager.board.board_zone.add_card(card), "faith test card is added to BoardZone")
	return card


func _horizontal_card_center(board: Board, left_cell: Vector2i) -> Vector2:
	var background := board.board_zone.back_ground
	var center_local := Vector2(
		(float(left_cell.x) + 1.0) * background.cell_size,
		(float(left_cell.y) + 0.5) * background.cell_size
	)
	return board.to_local(background.to_global(center_local))


func _move_card_center_to(card: Card, global_center: Vector2) -> void:
	card.global_position = global_center - card.size * 0.5
	card.target_position = card.position


func _cleanup_manager(manager: Node) -> void:
	if manager != null and is_instance_valid(manager):
		manager.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
