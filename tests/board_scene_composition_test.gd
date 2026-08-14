extends SceneTree

const BOARD_SCENE := preload("res://scenes/game/board.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")

var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_board_scene_contains_independent_zones()
	await _test_guide_commits_before_return_request()
	quit(1 if _failures > 0 else 0)

func _test_board_scene_contains_independent_zones() -> void:
	var board := BOARD_SCENE.instantiate() as Board
	root.add_child(board)
	await process_frame
	_expect(board.board_zone is BoardZone, "Board exposes BoardZone")
	_expect(board.event_zone is BoardEventZone, "Board exposes BoardEventZone")
	_expect(board.get_node_or_null("BoardZone") == board.board_zone, "BoardZone is a direct child")
	_expect(board.get_node_or_null("BoardEventZone") == board.event_zone, "BoardEventZone is a direct child")
	_expect(not board.has_method("get_card_cells"), "Board does not proxy card spatial queries")
	_expect(not board.has_method("get_event_cells"), "Board does not proxy event spatial queries")
	board.queue_free()
	await process_frame

func _test_guide_commits_before_return_request() -> void:
	var board := BOARD_SCENE.instantiate() as Board
	root.add_child(board)
	await process_frame
	var order: Array[String] = []
	board.placement_committed.connect(func(_result: BoardPlacementResult) -> void: order.append("placement"))
	board.card_return_requested.connect(func(card: Card) -> void:
		order.append("return")
		card.get_card_inst().cur_zone = CardInstance.ZONE.HAND
	)
	var root_card := _make_card(CardData.CardType.ROOT)
	root.add_child(root_card)
	_move_card_to_anchor(board.board_zone, root_card, Vector2i(4, 4), 0)
	_expect(board.board_zone.add_card(root_card), "root card can establish guide chain")
	order.clear()
	var guide := _make_card(CardData.CardType.GUIDE)
	root.add_child(guide)
	_move_card_to_anchor(board.board_zone, guide, Vector2i(4, 2), 0)
	_expect(board.board_zone.add_card(guide), "guide placement commits")
	_expect(order == ["placement", "return"], "guide placement commits before return request")
	board.queue_free()
	root_card.queue_free()
	guide.queue_free()
	await process_frame

func _move_card_to_anchor(board_zone: BoardZone, card: Card, anchor: Vector2i, direction: int) -> void:
	var background := board_zone.back_ground
	var cell_size := background.cell_size
	var local_center := Vector2(
		(float(anchor.x) + 0.5) * cell_size,
		(float(anchor.y) + 1.0) * cell_size
	)
	if posmod(direction, 4) % 2 == 1:
		local_center = Vector2(
			(float(anchor.x) + 1.0) * cell_size,
			(float(anchor.y) + 0.5) * cell_size
		)
	card.global_position = background.to_global(local_center) - card.size * 0.5
	card.target_position = card.position
	card.get_card_inst().direction = direction

func _make_card(card_type: CardData.CardType) -> Card:
	var data := CardData.new()
	data.card_type = card_type
	var instance := CardInstance.new(data)
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(instance)
	return card

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
