extends SceneTree

const BOARD_ZONE_SCENE := preload("res://scenes/zone/board_zone.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(CardData.CardType.GUIDE != CardData.CardType.NORMAL, "GUIDE remains a distinct CardType")

	var board := BOARD_ZONE_SCENE.instantiate() as BoardZone
	root.add_child(board)
	await process_frame
	var operations: Array[BoardCardPlacement] = []
	if board.has_signal("placement_applied"):
		board.placement_applied.connect(func(operation: BoardCardPlacement) -> void:
			operations.append(operation)
		)

	var root_card := _make_card(CardData.CardType.ROOT, 0, "Root")
	root.add_child(root_card)
	await process_frame
	_move_card_to_anchor(board, root_card, Vector2i(4, 4), 0)
	_expect(board.add_card(root_card), "ROOT fixture commits")

	var tail := _make_card(CardData.CardType.NORMAL, 0, "Tail")
	root.add_child(tail)
	await process_frame
	_move_card_to_anchor(board, tail, Vector2i(4, 2), 0)
	_expect(board.add_card(tail), "tail fixture commits")

	operations.clear()
	var root_instance := root_card.get_card_inst()
	var tail_instance := tail.get_card_inst()
	var guide := _make_card(CardData.CardType.GUIDE, 0, "Guide")
	root.add_child(guide)
	await process_frame
	_move_card_to_anchor(board, guide, Vector2i(4, 0), 0)
	var guide_cells := board.get_card_cells(guide)
	_expect(board.drag_end_target(guide, true), "GUIDE resolves against the chain endpoint")
	_expect(operations.size() == 1, "GUIDE emits one structured placement")
	if operations.size() == 1:
		var operation := operations[0]
		_expect(operation.kind == BoardCardPlacement.Kind.GUIDE_SHIFTED, "GUIDE operation uses GUIDE_SHIFTED")
		_expect(operation.card == guide, "GUIDE operation retains the source Card")
		_expect(operation.card_inst == guide.get_card_inst(), "GUIDE operation retains the exact CardInstance")
		_expect(operation.occupied_cells == guide_cells, "GUIDE reports the endpoint cells")
		_expect(operation.affected_cards == [root_card, tail], "GUIDE reports the chain in original order")
		_expect(operation.chain_tail == tail, "GUIDE reports the shifted chain tail")
	_expect(not board.owns_card(guide), "GUIDE never becomes a stable BoardZone member")
	_expect(board.get_cards() == [root_card, tail], "GUIDE preserves chain order")
	_expect(root_card.get_card_inst() == root_instance and tail.get_card_inst() == tail_instance, "GUIDE preserves exact CardInstance identity")
	_expect(root_instance.battlefield_pos == Vector2i(4, 2), "ROOT moves into the previous tail layout")
	_expect(tail_instance.battlefield_pos == Vector2i(4, 0), "tail moves into the GUIDE layout")
	_expect(board.get_card_at(Vector2i(4, 0)) == tail, "shifted tail owns the GUIDE endpoint")

	board.free()
	quit(1 if _failures > 0 else 0)


func _make_card(card_type: CardData.CardType, direction: int, card_name: String) -> Card:
	var data := CardData.new()
	data.card_type = card_type
	data.card_name = card_name
	var instance := CardInstance.new(data)
	instance.direction = direction
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(instance)
	return card


func _move_card_to_anchor(board: BoardZone, card: Card, anchor: Vector2i, direction: int) -> void:
	var background := board.back_ground
	var cell_size := background.cell_size
	var local_center := Vector2((float(anchor.x) + 0.5) * cell_size, (float(anchor.y) + 1.0) * cell_size)
	if posmod(direction, 4) % 2 == 1:
		local_center = Vector2((float(anchor.x) + 1.0) * cell_size, (float(anchor.y) + 0.5) * cell_size)
	card.global_position = background.to_global(local_center) - card.size * 0.5
	card.target_position = card.position
	card.get_card_inst().direction = direction


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
