extends SceneTree

const BoardScene := preload("res://scenes/game/board.tscn")
const HandScene := preload("res://scenes/game/hand.tscn")
const CardEntityScene := preload("res://scenes/card_view/card_entity.tscn")
const DragLayerScript := preload("res://scripts/game/drag_layer.gd")
const FaithServiceScript := preload("res://scripts/player/faith_service.gd")

var _failure_count := 0

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	await _test_cancelled_board_drag_does_not_spend_faith()
	await _test_confirmed_retraction_at_non_positive_faith_requests_echo()
	await _test_confirmed_retraction_bypasses_full_hand_capacity()
	await _test_guide_return_does_not_spend_faith()
	quit(1 if _failure_count > 0 else 0)

func _test_cancelled_board_drag_does_not_spend_faith() -> void:
	var fixture := await _make_fixture()
	var player := PlayerData.new()
	player.faith = 3
	var faith_service := FaithServiceScript.new()
	faith_service.configure(player)
	var echo_spawns: Array[bool] = []
	faith_service.echo_spawn_requested.connect(func() -> void: echo_spawns.append(true))
	_expect(fixture.drag_layer.has_signal("chain_retraction_confirmed"), "DragLayer publishes confirmed chain retractions")
	_expect(faith_service.has_method("resolve_confirmed_chain_retraction"), "FaithService resolves confirmed retractions")
	if fixture.drag_layer.has_signal("chain_retraction_confirmed") and faith_service.has_method("resolve_confirmed_chain_retraction"):
		fixture.drag_layer.connect("chain_retraction_confirmed", Callable(faith_service, "resolve_confirmed_chain_retraction"))

	fixture.drag_layer.on_card_drag_start(fixture.middle)
	fixture.drag_layer.set_interaction_locked(true)
	await process_frame

	_expect(player.faith == 3, "cancelling a board drag does not spend faith")
	_expect(echo_spawns.is_empty(), "cancelling a board drag does not request an echo")
	_expect(fixture.board.cards == [fixture.root_card, fixture.middle, fixture.tail], "interaction-lock cancellation restores the entire original chain")
	_expect(fixture.hand.cards.is_empty(), "interaction-lock cancellation does not leave followers in hand")
	await _cleanup_fixture(fixture)

func _test_confirmed_retraction_at_non_positive_faith_requests_echo() -> void:
	var fixture := await _make_fixture()
	var player := PlayerData.new()
	player.faith = 0
	var faith_service := FaithServiceScript.new()
	faith_service.configure(player)
	var echo_spawns: Array[bool] = []
	faith_service.echo_spawn_requested.connect(func() -> void: echo_spawns.append(true))
	var transactions: Array = []
	_expect(fixture.drag_layer.has_signal("chain_retraction_confirmed"), "DragLayer exposes the confirmed retraction signal")
	_expect(faith_service.has_method("resolve_confirmed_chain_retraction"), "FaithService accepts a confirmed retraction transaction")
	if fixture.drag_layer.has_signal("chain_retraction_confirmed"):
		fixture.drag_layer.connect("chain_retraction_confirmed", func(transaction) -> void: transactions.append(transaction))
	if fixture.drag_layer.has_signal("chain_retraction_confirmed") and faith_service.has_method("resolve_confirmed_chain_retraction"):
		fixture.drag_layer.connect("chain_retraction_confirmed", Callable(faith_service, "resolve_confirmed_chain_retraction"))

	fixture.drag_layer.on_card_drag_start(fixture.middle)
	fixture.middle.global_position = Vector2(-1000, -1000)
	fixture.drag_layer.on_card_drag_end(fixture.middle)
	await process_frame

	_expect(player.faith == -1, "a completed manual retraction spends faith even at zero")
	_expect(echo_spawns.size() == 1, "a completed non-positive faith retraction requests exactly one echo")
	_expect(transactions.size() == 1, "only a completed retraction publishes one transaction")
	if transactions.size() == 1:
		var transaction = transactions[0]
		_expect(transaction.removed_card == fixture.middle, "transaction records the dragged card")
		_expect(transaction.returned_followers == [fixture.tail], "transaction records the returned followers")
		_expect(transaction.original_chain_size == 3, "transaction retains the original chain size")
	_expect(fixture.middle in fixture.hand.cards and fixture.tail in fixture.hand.cards, "completed retraction returns the selected card and followers to hand")
	_expect(fixture.board.cards == [fixture.root_card], "completed retraction leaves the retained chain on the board")
	await _cleanup_fixture(fixture)

func _test_confirmed_retraction_bypasses_full_hand_capacity() -> void:
	var fixture := await _make_fixture()
	fixture.hand.max_hand_size = 1
	var retained_hand_card := _make_card(CardData.CardType.NORMAL)
	_expect(fixture.hand.add_card(retained_hand_card, false), "full-hand setup retains an existing card")
	var player := PlayerData.new()
	player.faith = 1
	var faith_service := FaithServiceScript.new()
	faith_service.configure(player)
	var transactions: Array = []
	fixture.drag_layer.chain_retraction_confirmed.connect(func(transaction) -> void: transactions.append(transaction))
	fixture.drag_layer.chain_retraction_confirmed.connect(Callable(faith_service, "resolve_confirmed_chain_retraction"))

	fixture.drag_layer.on_card_drag_start(fixture.middle)
	fixture.middle.global_position = Vector2(-1000, -1000)
	fixture.drag_layer.on_card_drag_end(fixture.middle)
	await process_frame

	_expect(player.faith == 0, "a confirmed retraction spends faith even while the hand is full")
	_expect(transactions.size() == 1, "a full hand does not suppress the confirmed retraction transaction")
	_expect(
		fixture.hand.cards == [retained_hand_card, fixture.tail, fixture.middle],
		"retraction returns all existing chain cards despite the configured hand limit"
	)
	_expect(fixture.hand.max_hand_size == 1, "forced retraction return restores the configured hand capacity")
	_expect(fixture.board.cards == [fixture.root_card], "full-hand retraction still removes the selected suffix from the board")
	await _cleanup_fixture(fixture)

func _test_guide_return_does_not_spend_faith() -> void:
	var fixture := await _make_fixture()
	var player := PlayerData.new()
	player.faith = 3
	var faith_service := FaithServiceScript.new()
	faith_service.configure(player)
	var transactions: Array = []
	_expect(fixture.drag_layer.has_signal("chain_retraction_confirmed"), "DragLayer keeps confirmed retractions distinct from automatic returns")
	if fixture.drag_layer.has_signal("chain_retraction_confirmed"):
		fixture.drag_layer.connect("chain_retraction_confirmed", func(transaction) -> void: transactions.append(transaction))
		if faith_service.has_method("resolve_confirmed_chain_retraction"):
			fixture.drag_layer.connect("chain_retraction_confirmed", Callable(faith_service, "resolve_confirmed_chain_retraction"))
	var guide := _make_card(CardData.CardType.GUIDE)
	guide.position = fixture.board.grid_to_world_center(Vector2i(5, 1))
	guide.rotation_degrees = 90.0
	fixture.board.card_return_requested.connect(func(card: CardEntity) -> void: fixture.hand.add_card(card, false))
	_expect(fixture.board.add_card(guide), "guide placement resolves normally")
	await process_frame

	_expect(player.faith == 3, "the automatic GUIDE return does not spend faith")
	_expect(transactions.is_empty(), "the automatic GUIDE return does not publish a retraction transaction")
	_expect(guide in fixture.hand.cards, "the automatic GUIDE return still moves the guide into hand")
	await _cleanup_fixture(fixture)

func _make_fixture() -> Dictionary:
	var board := BoardScene.instantiate() as Board
	var hand := HandScene.instantiate() as HandArea
	var drag_layer := DragLayerScript.new() as DragLayer
	root.add_child(board)
	root.add_child(hand)
	root.add_child(drag_layer)
	drag_layer.board = board
	drag_layer.hand_area = hand
	var root_card := _make_card(CardData.CardType.ROOT)
	root_card.position = Vector2(156, 260)
	root_card.rotation_degrees = 0.0
	_expect(board.add_card(root_card), "fixture root card establishes the chain")
	var middle := _make_card(CardData.CardType.NORMAL)
	middle.position = board.grid_to_world_center(Vector2i(1, 1))
	middle.rotation_degrees = 90.0
	_expect(board.add_card(middle), "fixture middle card extends the chain")
	var tail := _make_card(CardData.CardType.NORMAL)
	tail.position = board.grid_to_world_center(Vector2i(3, 1))
	tail.rotation_degrees = 90.0
	_expect(board.add_card(tail), "fixture tail card extends the chain")
	await process_frame
	return {"board": board, "hand": hand, "drag_layer": drag_layer, "root_card": root_card, "middle": middle, "tail": tail}

func _make_card(card_type: CardData.CardType) -> CardEntity:
	var card := CardEntityScene.instantiate() as CardEntity
	var data := CardData.new()
	data.card_type = card_type
	data.card_name = "Retraction Test"
	card.bind_instance(CardInstance.new(data))
	root.add_child(card)
	return card

func _cleanup_fixture(fixture: Dictionary) -> void:
	for key in ["drag_layer", "hand", "board", "root_card", "middle", "tail"]:
		var node = fixture.get(key)
		if node != null and is_instance_valid(node):
			node.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)