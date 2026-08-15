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
	await _test_rotated_card_uses_visual_center_for_board_cells()
	await _test_canvas_transform_keeps_board_cell_calculation_stable()
	await _test_canvas_transform_keeps_drag_target_cell_calculation_stable()
	await _test_drag_target_center_drives_board_cells_before_spring_catches_up()
	await _test_direct_add_keeps_current_position_semantics()
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


func _test_rotated_card_uses_visual_center_for_board_cells() -> void:
	const EXPECTED_CELLS: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3)]
	var board_zone := BOARD_ZONE_SCENE.instantiate() as BoardZone
	root.add_child(board_zone)
	await process_frame

	var card := _make_card(CardData.CardType.ROOT, 1, "RotatedRoot")
	root.add_child(card)
	await process_frame

	var expected_center := Vector2(418.0, 367.0)
	card.position = expected_center - card.size * 0.5
	card.target_position = card.position
	card.rotation_degrees = 90.0
	_expect(
		_card_global_center(card).distance_to(expected_center) <= POSITION_TOLERANCE,
		"rotated fixture starts with its visual center over the expected board cells"
	)

	_expect(board_zone.add_card(card), "a visually rotated ROOT commits")
	_expect(
		board_zone.get_card_cells(card) == EXPECTED_CELLS,
		"a visually rotated ROOT occupies the cells under its visual center"
	)
	_expect(
		_card_global_center(card).distance_to(expected_center) <= POSITION_TOLERANCE,
		"a visually rotated ROOT remains centered after snapping"
	)

	board_zone.queue_free()
	await process_frame


func _test_canvas_transform_keeps_board_cell_calculation_stable() -> void:
	const EXPECTED_CELLS: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3)]
	var viewport := root.get_viewport()
	var original_canvas_transform := viewport.canvas_transform
	# 模拟 canvas_items 拉伸到较小窗口。不能加入抵消缩放误差的平移，
	# 否则错误的屏幕坐标仍可能碰巧落在相同格子。
	var test_canvas_transform := Transform2D.IDENTITY.scaled(Vector2(0.5, 0.5))
	viewport.canvas_transform = test_canvas_transform

	var gameplay_canvas := Node2D.new()
	gameplay_canvas.position = Vector2(43.0, 27.0)
	root.add_child(gameplay_canvas)
	var board_zone := BOARD_ZONE_SCENE.instantiate() as BoardZone
	board_zone.position = Vector2(237.0, 16.0)
	gameplay_canvas.add_child(board_zone)
	await process_frame

	var card := _make_card(CardData.CardType.ROOT, 1, "CanvasRoot")
	gameplay_canvas.add_child(card)
	await process_frame
	var board_center := _cells_global_center(board_zone, EXPECTED_CELLS)
	card.position = gameplay_canvas.get_global_transform().affine_inverse() * board_center - card.size * 0.5
	card.target_position = card.position
	card.rotation_degrees = 90.0

	_expect(
		board_zone.get_card_cells(card) == EXPECTED_CELLS,
		"canvas transforms do not change the board cells under the card center"
	)
	_expect(board_zone.add_card(card), "ROOT commits while a canvas transform is active")
	_expect(
		board_zone.get_card_cells(card) == EXPECTED_CELLS,
		"committed ROOT keeps the expected cells under a canvas transform"
	)

	gameplay_canvas.queue_free()
	viewport.canvas_transform = original_canvas_transform
	await process_frame


func _test_canvas_transform_keeps_drag_target_cell_calculation_stable() -> void:
	const EXPECTED_CELLS: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3)]
	const LAGGING_CELLS: Array[Vector2i] = [Vector2i(1, 3), Vector2i(2, 3)]
	var viewport := root.get_viewport()
	var original_canvas_transform := viewport.canvas_transform
	viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(0.5, 0.5))

	var gameplay_canvas := Node2D.new()
	gameplay_canvas.position = Vector2(43.0, 27.0)
	root.add_child(gameplay_canvas)
	var dragger := DraggerLayer.new()
	gameplay_canvas.add_child(dragger)
	var board_zone := BOARD_ZONE_SCENE.instantiate() as BoardZone
	board_zone.position = Vector2(237.0, 16.0)
	gameplay_canvas.add_child(board_zone)
	board_zone.set_drag_layer(dragger)
	await process_frame

	var card := _make_card(CardData.CardType.ROOT, 1, "CanvasFastDropRoot")
	gameplay_canvas.add_child(card)
	card.bind_drag_layer(dragger)
	await process_frame
	_expect(dragger.start_drag(card), "canvas fast-drop fixture starts a drag transaction")
	var lagging_center := _cells_global_center(board_zone, LAGGING_CELLS)
	var target_center := _cells_global_center(board_zone, EXPECTED_CELLS)
	var canvas_inverse := gameplay_canvas.get_global_transform().affine_inverse()
	card.position = canvas_inverse * lagging_center - card.size * 0.5
	card.target_position = canvas_inverse * target_center - card.size * 0.5
	card.rotation_degrees = 90.0

	_expect(
		board_zone.get_card_cells(card) == EXPECTED_CELLS,
		"canvas transforms do not change cells calculated from the drag target center"
	)

	gameplay_canvas.queue_free()
	viewport.canvas_transform = original_canvas_transform
	await process_frame


func _test_drag_target_center_drives_board_cells_before_spring_catches_up() -> void:
	const EXPECTED_CELLS: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3)]
	const LAGGING_CELLS: Array[Vector2i] = [Vector2i(1, 3), Vector2i(2, 3)]
	var dragger := DraggerLayer.new()
	root.add_child(dragger)
	var board_zone := BOARD_ZONE_SCENE.instantiate() as BoardZone
	root.add_child(board_zone)
	board_zone.set_drag_layer(dragger)
	await process_frame

	var card := _make_card(CardData.CardType.ROOT, 1, "FastDropRoot")
	root.add_child(card)
	card.bind_drag_layer(dragger)
	await process_frame
	_expect(dragger.start_drag(card), "fast-drop fixture starts a real drag transaction")
	var lagging_center := _cells_global_center(board_zone, LAGGING_CELLS)
	var target_center := _cells_global_center(board_zone, EXPECTED_CELLS)
	card.position = lagging_center - card.size * 0.5
	card.target_position = target_center - card.size * 0.5
	card.rotation_degrees = 90.0

	_expect(
		board_zone.get_card_cells(card) == EXPECTED_CELLS,
		"BoardZone uses the drag target center instead of the spring-lagging visual center"
	)
	_expect(dragger.end_drag(card), "fast-dropped ROOT commits through DraggerLayer")
	_expect(
		board_zone.get_card_cells(card) == EXPECTED_CELLS,
		"fast-dropped ROOT commits to the cells under its drag target"
	)
	_expect(
		_card_global_center(card).distance_to(target_center) <= POSITION_TOLERANCE,
		"fast-dropped ROOT snaps to its intended target center"
	)

	dragger.queue_free()
	board_zone.queue_free()
	await process_frame


func _test_direct_add_keeps_current_position_semantics() -> void:
	const EXPECTED_CELLS: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3)]
	const STALE_TARGET_CELLS: Array[Vector2i] = [Vector2i(1, 3), Vector2i(2, 3)]
	var board_zone := BOARD_ZONE_SCENE.instantiate() as BoardZone
	root.add_child(board_zone)
	await process_frame

	var card := _make_card(CardData.CardType.ROOT, 1, "DirectRoot")
	root.add_child(card)
	await process_frame
	var current_center := _cells_global_center(board_zone, EXPECTED_CELLS)
	var stale_target_center := _cells_global_center(board_zone, STALE_TARGET_CELLS)
	card.position = current_center - card.size * 0.5
	card.target_position = stale_target_center - card.size * 0.5
	card.rotation_degrees = 90.0

	_expect(
		board_zone.get_card_cells(card) == EXPECTED_CELLS,
		"direct placement still calculates cells from the current card center"
	)
	_expect(board_zone.add_card(card), "directly added ROOT commits")
	_expect(
		board_zone.get_card_cells(card) == EXPECTED_CELLS,
		"directly added ROOT does not use a stale drag target"
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
