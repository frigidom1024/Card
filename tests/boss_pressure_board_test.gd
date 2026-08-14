extends SceneTree

const BOARD_SCENE := preload("res://scenes/game/board.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")
const EVENT_SCENE := preload("res://scenes/game/event.tscn")
const EVENT_DATA := preload("res://scripts/game/event/core/event_data.gd")
const BOSS_PRESSURE_SERVICE := preload("res://scripts/game/exploration/boss_pressure_service.gd")
const BOARD_PLACEMENT_RESULT := preload("res://scripts/game/board_placement_result.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_intercepting_boss_allows_next_card_to_overlap()
	await _test_boss_pressure_intercepts_at_forward_cell_without_blocking_placement()
	await _test_guide_placement_does_not_advance_boss_pressure()
	quit(1 if _failure_count > 0 else 0)


func _test_intercepting_boss_allows_next_card_to_overlap() -> void:
	var board := _make_board()
	var root_card := _make_card(CardData.CardType.ROOT)
	_move_card_to_anchor(board.board_zone, root_card, Vector2i(4, 4), 0)
	_expect(board.board_zone.add_card(root_card), "root card establishes a chain tail")

	var intercept_cell: Vector2i = board.board_zone.get_placement_cell(root_card)
	var boss := _make_boss_event(intercept_cell)
	_expect(board.attach_event(boss), "boss can occupy the chain tail forward cell as an ordinary event")

	var candidate := _make_card(CardData.CardType.NORMAL)
	_move_card_to_anchor(board.board_zone, candidate, Vector2i(4, 2), 0)
	var candidate_cells: Array[Vector2i] = board.board_zone.get_card_cells(candidate)
	_expect(intercept_cell in candidate_cells, "candidate covers the boss intercept cell")
	_expect(board.board_zone.can_place_card(candidate), "an intercepting boss never makes its event cell illegal for placement")

	var results: Array[BoardPlacementResult] = []
	board.placement_committed.connect(
		func(result: BoardPlacementResult) -> void: results.append(result)
	)
	_expect(board.board_zone.add_card(candidate), "the next card can overlap the intercepting boss")
	_expect(results.size() == 1, "overlapping the boss publishes one placement transaction")
	if results.size() == 1:
		_expect(results[0].overlapped_event == boss.event_instance, "the placement result exposes the contacted boss event")
	board.queue_free()
	await process_frame


func _test_boss_pressure_intercepts_at_forward_cell_without_blocking_placement() -> void:
	var board := _make_board()
	var root_card := _make_card(CardData.CardType.ROOT)
	_move_card_to_anchor(board.board_zone, root_card, Vector2i(4, 4), 0)
	_expect(board.board_zone.add_card(root_card), "root card establishes a tail for Boss pressure")
	var boss := _make_boss_event(Vector2i(0, 0))
	_expect(board.attach_event(boss), "Boss attaches before pressure begins")

	var service := BOSS_PRESSURE_SERVICE.new()
	service.configure(true, 1, 1)
	service.register_boss(boss)
	service.record_card_placed(board)
	_expect(service.get_phase() == BOSS_PRESSURE_SERVICE.Phase.SURROUNDING, "Boss enters surrounding after the configured threshold")
	service.record_card_placed(board)
	_expect(service.get_phase() == BOSS_PRESSURE_SERVICE.Phase.INTERCEPTING, "Boss enters intercepting after the second configured threshold")
	_expect(boss.event_instance.origin == board.board_zone.get_placement_cell(root_card), "intercepting moves the ordinary Boss event to the tail forward cell")

	var candidate := _make_card(CardData.CardType.NORMAL)
	_move_card_to_anchor(board.board_zone, candidate, Vector2i(4, 2), 0)
	_expect(board.board_zone.can_place_card(candidate), "Boss pressure does not register an illegal placement blocker")
	candidate.free()
	board.queue_free()
	await process_frame


func _test_guide_placement_does_not_advance_boss_pressure() -> void:
	var board := _make_board()
	var root_card := _make_card(CardData.CardType.ROOT)
	_move_card_to_anchor(board.board_zone, root_card, Vector2i(4, 4), 0)
	_expect(board.board_zone.add_card(root_card), "root card establishes a chain before guide pressure verification")
	var boss := _make_boss_event(Vector2i(0, 0))
	_expect(board.attach_event(boss), "boss attaches before guide pressure verification")

	var service := BOSS_PRESSURE_SERVICE.new()
	service.configure(true, 1, 1)
	service.register_boss(boss)
	var guide := _make_card(CardData.CardType.GUIDE)
	_move_card_to_anchor(board.board_zone, guide, Vector2i(4, 2), 0)
	var guide_cells: Array[Vector2i] = board.board_zone.get_card_cells(guide)
	var guide_result := BOARD_PLACEMENT_RESULT.new(
		BOARD_PLACEMENT_RESULT.Kind.GUIDE_RESOLVED,
		guide,
		root_card,
		[root_card],
		guide_cells
	)

	service.record_placement(board, guide_result)
	_expect(service.get_phase() == BOSS_PRESSURE_SERVICE.Phase.ACTIVE, "guide resolution does not advance Boss pressure")
	guide.queue_free()
	board.queue_free()
	await process_frame


func _make_board() -> Board:
	var board := BOARD_SCENE.instantiate() as Board
	root.add_child(board)
	return board


func _make_card(card_type: CardData.CardType) -> Card:
	var card := CARD_SCENE.instantiate() as Card
	var data := CardData.new()
	data.card_type = card_type
	card.bind_card_inst(CardInstance.new(data))
	return card


func _move_card_to_anchor(board_zone: BoardZone, card: Card, anchor: Vector2i, direction: int) -> void:
	var background := board_zone.back_ground
	var cell_size := background.cell_size
	var local_center: Vector2
	if posmod(direction, 4) % 2 == 0:
		local_center = Vector2((float(anchor.x) + 0.5) * cell_size, (float(anchor.y) + 1.0) * cell_size)
	else:
		local_center = Vector2((float(anchor.x) + 1.0) * cell_size, (float(anchor.y) + 0.5) * cell_size)
	var center := background.to_global(local_center)
	card.global_position = center - card.size * 0.5
	card.target_position = card.position
	card.get_card_inst().direction = direction


func _make_boss_event(origin: Vector2i) -> BoardEvent:
	var data := EVENT_DATA.new()
	data.event_id = "test_boss"
	data.event_type = EVENT_DATA.EventType.BOSS
	data.size = Vector2i.ONE
	var instance := data.create_instance()
	instance.origin = origin
	var event_node := EVENT_SCENE.instantiate() as BoardEvent
	event_node.setup(instance, 84)
	return event_node


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
