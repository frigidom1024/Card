extends SceneTree

const BoardScene = preload("res://scenes/game/board.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const EventDataScript = preload("res://scripts/game/event/core/event_data.gd")
const BossPressureServiceScript = preload("res://scripts/game/exploration/boss_pressure_service.gd")
const BoardPlacementResultScript = preload("res://scripts/game/board_placement_result.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_intercepting_boss_allows_next_card_to_overlap()
	_test_boss_pressure_intercepts_at_forward_cell_without_blocking_placement()
	_test_guide_placement_does_not_advance_boss_pressure()
	quit(1 if _failure_count > 0 else 0)


func _test_intercepting_boss_allows_next_card_to_overlap() -> void:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	var root_card := _make_card(board, Vector2(280, 200), 0.0, CardData.CardType.ROOT)
	_expect(board.add_card(root_card), "root card establishes a chain tail")

	var intercept_cell := board.get_placement_cell(root_card)
	var boss := _make_boss_event(intercept_cell)
	_expect(board.attach_event(boss), "boss can occupy the chain tail forward cell as an ordinary event")

	var candidate := _make_card(board, Vector2(208, 52), 90.0, CardData.CardType.NORMAL)
	var candidate_cells := board.get_card_cells(candidate.global_position, candidate.rotation_degrees)
	_expect(intercept_cell in candidate_cells, "candidate covers the boss intercept cell")
	_expect(board.can_place_card(candidate_cells, candidate), "an intercepting boss never makes its event cell illegal for placement")

	var results: Array = []
	board.placement_committed.connect(func(result) -> void:
		results.append(result)
	)
	_expect(board.add_card(candidate), "the next card can overlap the intercepting boss")
	_expect(results.size() == 1, "overlapping the boss publishes one placement transaction")
	if results.size() == 1:
		_expect(results[0].overlapped_event == boss.event_instance, "the placement result exposes the contacted boss event")
	board.queue_free()


func _test_boss_pressure_intercepts_at_forward_cell_without_blocking_placement() -> void:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	var root_card := _make_card(board, Vector2(280, 200), 0.0, CardData.CardType.ROOT)
	_expect(board.add_card(root_card), "root card establishes a tail for Boss pressure")
	var boss := _make_boss_event(Vector2i(0, 0))
	_expect(board.attach_event(boss), "Boss attaches before pressure begins")

	var service := BossPressureServiceScript.new()
	service.configure(true, 1, 1)
	service.register_boss(boss)
	service.record_card_placed(board)
	_expect(service.get_phase() == BossPressureServiceScript.Phase.SURROUNDING, "Boss enters surrounding after the configured threshold")
	service.record_card_placed(board)
	_expect(service.get_phase() == BossPressureServiceScript.Phase.INTERCEPTING, "Boss enters intercepting after the second configured threshold")
	_expect(boss.event_instance.origin == board.get_placement_cell(root_card), "intercepting moves the ordinary Boss event to the tail forward cell")

	var candidate := _make_card(board, Vector2(208, 52), 90.0, CardData.CardType.NORMAL)
	var candidate_cells := board.get_card_cells(candidate.global_position, candidate.rotation_degrees)
	_expect(board.can_place_card(candidate_cells, candidate), "Boss pressure does not register an illegal placement blocker")
	board.queue_free()


func _test_guide_placement_does_not_advance_boss_pressure() -> void:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	var root_card := _make_card(board, Vector2(280, 200), 0.0, CardData.CardType.ROOT)
	_expect(board.add_card(root_card), "root card establishes a chain before guide pressure verification")
	var boss := _make_boss_event(Vector2i(0, 0))
	_expect(board.attach_event(boss), "boss attaches before guide pressure verification")

	var service := BossPressureServiceScript.new()
	service.configure(true, 1, 1)
	service.register_boss(boss)
	var guide := _make_card(board, Vector2(208, 52), 90.0, CardData.CardType.GUIDE)
	var guide_cells := board.get_card_cells(guide.global_position, guide.rotation_degrees)
	var guide_result := BoardPlacementResultScript.new(
		BoardPlacementResultScript.Kind.GUIDE_RESOLVED,
		guide,
		root_card,
		[root_card],
		guide_cells
	)

	service.record_placement(board, guide_result)
	_expect(service.get_phase() == BossPressureServiceScript.Phase.ACTIVE, "guide resolution does not advance Boss pressure")
	board.queue_free()

func _make_card(board: Board, position: Vector2, rotation_degrees: float, card_type: CardData.CardType) -> CardEntity:
	var card := CardEntityScene.instantiate() as CardEntity
	board.add_child(card)
	card.position = position
	card.rotation_degrees = rotation_degrees
	var data := CardData.new()
	data.card_type = card_type
	card.card_instance = CardInstance.new(data)
	return card


func _make_boss_event(origin: Vector2i) -> BoardEvent:
	var data := EventDataScript.new()
	data.event_id = "test_boss"
	data.event_type = EventDataScript.EventType.BOSS
	data.size = Vector2i.ONE
	var instance := data.create_instance()
	instance.origin = origin
	var event_node := EventScene.instantiate() as BoardEvent
	event_node.setup(instance, 80)
	return event_node


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
