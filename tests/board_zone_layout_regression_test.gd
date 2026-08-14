extends SceneTree

const BOARD_SCENE := preload("res://scenes/game/board.tscn")
const BOARD_ZONE_SCENE := preload("res://scenes/zone/board_zone.tscn")
const HAND_ZONE_SCENE := preload("res://scenes/zone/handzone.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")
const POSITION_TOLERANCE := 0.1

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_committed_card_stays_centered_on_occupied_cells()
	await _test_guide_shift_rebuilds_layout_from_board_cells()
	quit(1 if _failures > 0 else 0)


func _test_committed_card_stays_centered_on_occupied_cells() -> void:
	for direction in range(4):
		var board_zone := BOARD_ZONE_SCENE.instantiate() as BoardZone
		root.add_child(board_zone)
		await process_frame

		var card := _make_card(CardData.CardType.ROOT, direction, "Root%d" % direction)
		root.add_child(card)
		await process_frame
		_move_card_to_anchor(board_zone, card, Vector2i(3, 3), direction)
		_expect(board_zone.add_card(card), "direction %d ROOT commits" % direction)

		var cells := board_zone.get_card_cells(card)
		var expected_center := _cells_global_center(board_zone, cells)
		_expect(
			_card_global_center(card).distance_to(expected_center) <= POSITION_TOLERANCE,
			"direction %d card center matches its two occupied cells" % direction
		)
		await _wait_frames(30)
		_expect(
			_card_global_center(card).distance_to(expected_center) <= POSITION_TOLERANCE,
			"direction %d card remains centered after spring updates" % direction
		)

		board_zone.queue_free()
		await process_frame


func _test_guide_shift_rebuilds_layout_from_board_cells() -> void:
	var board := BOARD_SCENE.instantiate() as Board
	root.add_child(board)
	var hand_zone := HAND_ZONE_SCENE.instantiate() as HandZone
	hand_zone.float_amplitude = 0.0
	root.add_child(hand_zone)
	await process_frame
	hand_zone.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hand_zone.position = Vector2(1500.0, -900.0)
	hand_zone.size = Vector2(800.0, 240.0)

	board.card_return_requested.connect(func(card: Card) -> void:
		hand_zone.add_card(card, true)
	)

	var root_card := _make_card(CardData.CardType.ROOT, 0, "Root")
	root.add_child(root_card)
	await process_frame
	_move_card_to_anchor(board.board_zone, root_card, Vector2i(4, 4), 0)
	_expect(board.board_zone.add_card(root_card), "ROOT fixture commits")

	var tail := _make_card(CardData.CardType.NORMAL, 0, "Tail")
	root.add_child(tail)
	await process_frame
	_move_card_to_anchor(board.board_zone, tail, Vector2i(4, 2), 0)
	_expect(board.board_zone.add_card(tail), "tail fixture commits")
	var old_tail_cells := board.board_zone.get_card_cells(tail)

	var guide := _make_card(CardData.CardType.GUIDE, 0, "Guide")
	root.add_child(guide)
	await process_frame
	_expect(hand_zone.add_card(guide, false), "GUIDE starts in HandZone")
	_move_card_to_anchor(board.board_zone, guide, Vector2i(4, 0), 0)
	var guide_cells := board.board_zone.get_card_cells(guide)
	_expect(board.board_zone.add_card(guide, true), "GUIDE resolves against the endpoint")

	_expect(hand_zone.owns_card(guide), "resolved GUIDE returns to HandZone")
	_expect(board.board_zone.get_card_cells(root_card) == old_tail_cells, "ROOT takes the old tail cells")
	_expect(board.board_zone.get_card_cells(tail) == guide_cells, "tail takes the GUIDE cells")

	var expected_root_center := _cells_global_center(board.board_zone, old_tail_cells)
	var expected_tail_center := _cells_global_center(board.board_zone, guide_cells)
	await _wait_frames(60)
	_expect(
		_card_global_center(root_card).distance_to(expected_root_center) <= POSITION_TOLERANCE,
		"GUIDE-shifted ROOT remains centered on its new cells"
	)
	_expect(
		_card_global_center(tail).distance_to(expected_tail_center) <= POSITION_TOLERANCE,
		"GUIDE-shifted tail remains centered instead of following HandZone-local coordinates"
	)
	_expect(
		tail.target_position.distance_to(tail.position) <= POSITION_TOLERANCE,
		"GUIDE-shifted tail target is rebuilt in BoardZone-local coordinates"
	)

	board.queue_free()
	hand_zone.queue_free()
	await process_frame


func _make_card(card_type: CardData.CardType, direction: int, card_name: String) -> Card:
	var data := CardData.new()
	data.card_type = card_type
	data.card_name = card_name
	var instance := CardInstance.new(data)
	instance.direction = direction
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(instance)
	return card


func _move_card_to_anchor(
	board_zone: BoardZone,
	card: Card,
	anchor: Vector2i,
	direction: int
) -> void:
	var cells: Array[Vector2i] = [anchor]
	if posmod(direction, 4) % 2 == 0:
		cells.append(anchor + Vector2i(0, 1))
	else:
		cells.append(anchor + Vector2i(1, 0))
	var center := _cells_global_center(board_zone, cells)
	card.global_position = center - card.size * 0.5
	card.target_position = card.position
	card.get_card_inst().direction = direction


func _cells_global_center(board_zone: BoardZone, cells: Array[Vector2i]) -> Vector2:
	var center := Vector2.ZERO
	for cell in cells:
		center += board_zone.back_ground.to_global(
			(Vector2(cell) + Vector2(0.5, 0.5)) * board_zone.back_ground.cell_size
		)
	return center / float(cells.size())


func _card_global_center(card: Card) -> Vector2:
	return card.get_global_transform_with_canvas() * (card.size * 0.5)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
