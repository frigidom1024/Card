extends SceneTree

const BOARD_SCENE := preload("res://scenes/game/board.tscn")
const HAND_ZONE_SCENE := preload("res://scenes/zone/handzone.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")
const DRAGGER_LAYER_SCENE := preload("res://scenes/drag_layer/dragger_layer.tscn")
const RETRACTION_COST_SERVICE_SCRIPT := preload("res://scripts/game/run/card_retraction_cost_service.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_cancelled_board_drag_does_not_spend_gold()
	await _test_confirmed_retraction_publishes_transaction_and_spends_gold()
	await _test_confirmed_retraction_returns_followers_at_display_capacity()
	await _test_guide_return_does_not_publish_retraction_or_spend_gold()
	quit(1 if _failure_count > 0 else 0)


func _test_cancelled_board_drag_does_not_spend_gold() -> void:
	var fixture := await _make_fixture()
	var player := PlayerData.new()
	player.gold = 10
	var cost_service := RETRACTION_COST_SERVICE_SCRIPT.new() as CardRetractionCostService
	cost_service.configure(player)
	fixture.board.chain_retraction_confirmed.connect(cost_service.resolve_confirmed_chain_retraction)
	var transactions: Array[ChainRetractionTransaction] = []
	fixture.board.chain_retraction_confirmed.connect(func(transaction: ChainRetractionTransaction) -> void:
		transactions.append(transaction)
	)

	_expect(fixture.drag_layer.start_drag(fixture.middle), "DraggerLayer starts a board-card drag")
	fixture.middle.global_position = Vector2(1750.0, 850.0)
	_expect(
		fixture.drag_layer.end_drag(fixture.middle),
		"dropping outside every zone completes the cancelled drag lifecycle"
	)

	_expect(player.gold == 10, "a cancelled board drag does not spend gold")
	_expect(transactions.is_empty(), "a cancelled board drag does not publish a retraction transaction")
	_expect(
		fixture.board.board_zone.get_cards() == [fixture.root_card, fixture.middle, fixture.tail],
		"a cancelled board drag restores the complete original chain"
	)
	_expect(fixture.hand_zone.get_cards().is_empty(), "a cancelled board drag returns no card to hand")
	await _cleanup_fixture(fixture)


func _test_confirmed_retraction_publishes_transaction_and_spends_gold() -> void:
	var fixture := await _make_fixture()
	var player := PlayerData.new()
	player.gold = 10
	var cost_service := RETRACTION_COST_SERVICE_SCRIPT.new() as CardRetractionCostService
	cost_service.configure(player)
	var transactions: Array[ChainRetractionTransaction] = []
	fixture.board.chain_retraction_confirmed.connect(func(transaction: ChainRetractionTransaction) -> void:
		transactions.append(transaction)
	)
	fixture.board.chain_retraction_confirmed.connect(cost_service.resolve_confirmed_chain_retraction)

	_expect(fixture.drag_layer.start_drag(fixture.middle), "DraggerLayer starts the confirmed retraction")
	_move_card_center_to(fixture.middle, fixture.hand_zone.get_global_rect().get_center())
	_expect(fixture.drag_layer.end_drag(fixture.middle), "HandZone accepts the selected board card")

	_expect(transactions.size() == 1, "one completed retraction publishes one transaction")
	if transactions.size() == 1:
		var transaction := transactions[0]
		_expect(transaction.removed_card == fixture.middle, "transaction records the selected card")
		_expect(transaction.returned_followers == [fixture.tail], "transaction records returned followers in chain order")
		_expect(transaction.original_chain_size == 3, "transaction retains the original chain size")
	_expect(player.gold == 6, "the selected card and one returned follower cost four gold")
	_expect(fixture.hand_zone.owns_card(fixture.middle), "the selected card becomes a HandZone member")
	_expect(fixture.hand_zone.owns_card(fixture.tail), "the detached follower returns through Board.card_return_requested")
	_expect(fixture.board.board_zone.get_cards() == [fixture.root_card], "the retained prefix stays on BoardZone")
	_expect(fixture.middle.get_card_inst().cur_zone == CardInstance.ZONE.HAND, "the selected CardInstance enters HAND")
	_expect(fixture.tail.get_card_inst().cur_zone == CardInstance.ZONE.HAND, "the follower CardInstance enters HAND")
	await _cleanup_fixture(fixture)


func _test_confirmed_retraction_returns_followers_at_display_capacity() -> void:
	var fixture := await _make_fixture()
	fixture.hand_zone.display_capacity = 1
	var retained_hand_card := _make_card(CardData.CardType.NORMAL, 0, "Retained Hand Card")
	root.add_child(retained_hand_card)
	await process_frame
	retained_hand_card.bind_drag_layer(fixture.drag_layer)
	_expect(fixture.hand_zone.add_card(retained_hand_card, true), "fixture fills the displayed hand capacity")
	var transactions: Array[ChainRetractionTransaction] = []
	fixture.board.chain_retraction_confirmed.connect(func(transaction: ChainRetractionTransaction) -> void:
		transactions.append(transaction)
	)

	_expect(fixture.drag_layer.start_drag(fixture.middle), "DraggerLayer starts a retraction at display capacity")
	_move_card_center_to(fixture.middle, fixture.hand_zone.get_global_rect().get_center())
	_expect(fixture.drag_layer.end_drag(fixture.middle), "HandZone remains a valid return target at display capacity")

	_expect(transactions.size() == 1, "display capacity does not suppress the retraction transaction")
	_expect(fixture.hand_zone.owns_card(retained_hand_card), "the existing hand card is retained")
	_expect(fixture.hand_zone.owns_card(fixture.middle), "the selected card is accepted")
	_expect(fixture.hand_zone.owns_card(fixture.tail), "the follower is synchronously returned")
	_expect(fixture.hand_zone.get_card_count() == 3, "all exact Card views remain in the hand")
	_expect(fixture.hand_zone.display_capacity == 1, "return routing does not mutate display capacity")
	await _cleanup_fixture(fixture)


func _test_guide_return_does_not_publish_retraction_or_spend_gold() -> void:
	var fixture := await _make_fixture()
	var player := PlayerData.new()
	player.gold = 10
	var cost_service := RETRACTION_COST_SERVICE_SCRIPT.new() as CardRetractionCostService
	cost_service.configure(player)
	var transactions: Array[ChainRetractionTransaction] = []
	fixture.board.chain_retraction_confirmed.connect(func(transaction: ChainRetractionTransaction) -> void:
		transactions.append(transaction)
	)
	fixture.board.chain_retraction_confirmed.connect(cost_service.resolve_confirmed_chain_retraction)
	var guide := _make_card(CardData.CardType.GUIDE, 1, "Guide")
	var guide_instance := guide.get_card_inst()
	root.add_child(guide)
	await process_frame
	_move_card_to_anchor(fixture.board.board_zone, guide, Vector2i(6, 3), 1)

	_expect(fixture.board.board_zone.add_card(guide), "GUIDE resolves at the current chain endpoint")
	_expect(player.gold == 10, "automatic GUIDE return does not spend gold")
	_expect(transactions.is_empty(), "automatic GUIDE return does not publish a chain retraction")
	_expect(fixture.hand_zone.owns_card(guide), "GUIDE returns through the shared Board return signal")
	_expect(guide.get_card_inst() == guide_instance, "GUIDE return preserves the exact CardInstance")
	_expect(guide_instance.cur_zone == CardInstance.ZONE.HAND, "returned GUIDE enters HAND")
	await _cleanup_fixture(fixture)


func _make_fixture() -> Dictionary:
	var board := BOARD_SCENE.instantiate() as Board
	var hand_zone := HAND_ZONE_SCENE.instantiate() as HandZone
	var drag_layer := DRAGGER_LAYER_SCENE.instantiate() as DraggerLayer
	root.add_child(board)
	root.add_child(hand_zone)
	root.add_child(drag_layer)
	await process_frame

	hand_zone.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hand_zone.position = Vector2(1050.0, 100.0)
	hand_zone.size = Vector2(700.0, 360.0)
	hand_zone.float_amplitude = 0.0
	drag_layer.register_zone(hand_zone)
	board.board_zone.set_drag_layer(drag_layer)
	board.card_return_requested.connect(func(card: Card) -> void:
		if not hand_zone.add_card(card, true):
			push_error("retraction fixture failed to return Card to HandZone")
	)

	var root_card := _make_card(CardData.CardType.ROOT, 1, "Root")
	var middle := _make_card(CardData.CardType.NORMAL, 1, "Middle")
	var tail := _make_card(CardData.CardType.NORMAL, 1, "Tail")
	root.add_child(root_card)
	root.add_child(middle)
	root.add_child(tail)
	await process_frame
	_move_card_to_anchor(board.board_zone, root_card, Vector2i(0, 3), 1)
	_expect(board.board_zone.add_card(root_card), "fixture ROOT establishes the chain")
	_move_card_to_anchor(board.board_zone, middle, Vector2i(2, 3), 1)
	_expect(board.board_zone.add_card(middle), "fixture middle card extends the chain")
	_move_card_to_anchor(board.board_zone, tail, Vector2i(4, 3), 1)
	_expect(board.board_zone.add_card(tail), "fixture tail card extends the chain")

	return {
		"board": board,
		"hand_zone": hand_zone,
		"drag_layer": drag_layer,
		"root_card": root_card,
		"middle": middle,
		"tail": tail,
	}


func _make_card(card_type: CardData.CardType, direction: int, card_name: String) -> Card:
	var data := CardData.new()
	data.card_type = card_type
	data.card_name = card_name
	var instance := CardInstance.new(data)
	instance.direction = direction
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(instance)
	return card


func _move_card_to_anchor(board_zone: BoardZone, card: Card, anchor: Vector2i, direction: int) -> void:
	var cell_size := board_zone.back_ground.cell_size
	var local_center := Vector2(
		(float(anchor.x) + 0.5) * cell_size,
		(float(anchor.y) + 1.0) * cell_size
	)
	if posmod(direction, 4) % 2 == 1:
		local_center = Vector2(
			(float(anchor.x) + 1.0) * cell_size,
			(float(anchor.y) + 0.5) * cell_size
		)
	var center := board_zone.back_ground.to_global(local_center)
	_move_card_center_to(card, center)
	card.target_position = card.position
	card.get_card_inst().direction = direction


func _move_card_center_to(card: Card, global_center: Vector2) -> void:
	card.global_position = global_center - card.size * 0.5
	card.target_position = card.position


func _cleanup_fixture(fixture: Dictionary) -> void:
	for key in ["drag_layer", "hand_zone", "board"]:
		var node := fixture.get(key) as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
