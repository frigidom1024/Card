extends SceneTree

const BoardScene = preload("res://scenes/game/board.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const CardDataScript = preload("res://scripts/card/card_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const EventDataScript = preload("res://scripts/game/event/event_data.gd")
const EventInstanceScript = preload("res://scripts/game/event/event_zone.gd")

var _failure_count := 0


func _init() -> void:
	_test_event_placement_reserves_a_one_cell_gap()
	_test_successful_card_placement_triggers_exactly_one_event()
	_test_resolved_or_failed_placement_never_triggers()
	_test_preview_never_triggers()
	call_deferred("_finish_tests")


func _test_event_placement_reserves_a_one_cell_gap() -> void:
	var board := _make_board(5, 1)
	_attach_event(board, "first", Vector2i(0, 0), Vector2i.ONE)
	var second := _new_event("second", Vector2i.ONE, Vector2i(1, 0))
	_expect(not board.can_attach_event(second.event_instance), "one empty cell is required")
	second.free()


func _test_successful_card_placement_triggers_exactly_one_event() -> void:
	var board := _make_board(5, 2)
	_attach_event(board, "treasure", Vector2i(2, 0), Vector2i.ONE)
	var card := _make_card_at(board, Vector2(120, 40), 90.0)
	var triggered: Array[EventInstance] = []
	board.event_triggered.connect(func(instance): triggered.append(instance))
	_expect(board.add_card(card), "card is legally placed")
	_expect(
		triggered.size() == 1 and triggered[0].template.event_id == "treasure",
		"overlap emits matching event"
	)


func _test_resolved_or_failed_placement_never_triggers() -> void:
	var board := _make_board(3, 2)
	var event_node := _attach_event(board, "resolved", Vector2i(1, 0), Vector2i.ONE)
	event_node.event_instance.resolve()
	var trigger_count := 0
	board.event_triggered.connect(func(_instance): trigger_count += 1)
	board.add_card(_make_card_at(board, Vector2(120, 40), 90.0))
	board.add_card(_make_card_at(board, Vector2(-80, 40), 90.0))
	_expect(trigger_count == 0, "resolved and rejected placements do not trigger")


func _test_preview_never_triggers() -> void:
	var board := _make_board(5, 2)
	_attach_event(board, "preview-only", Vector2i(2, 0), Vector2i.ONE)
	var trigger_count := 0
	board.event_triggered.connect(func(_instance): trigger_count += 1)
	board.preview_card(_make_card_at(board, Vector2(120, 40), 90.0))
	_expect(trigger_count == 0, "preview does not trigger events")


func _make_board(board_width: int, board_height: int) -> Board:
	var board := BoardScene.instantiate() as Board
	board.width = board_width
	board.height = board_height
	root.add_child(board)
	return board


func _new_event(event_id: String, event_size: Vector2i, origin: Vector2i) -> BoardEvent:
	var template := EventDataScript.new()
	template.event_id = event_id
	template.size = event_size
	var instance := EventInstanceScript.new()
	instance.template = template
	instance.origin = origin
	var event_node := EventScene.instantiate() as BoardEvent
	event_node.setup(instance, 80)
	return event_node


func _attach_event(board: Board, event_id: String, origin: Vector2i, event_size: Vector2i) -> BoardEvent:
	var event_node := _new_event(event_id, event_size, origin)
	_expect(board.attach_event(event_node), "event attaches to board")
	return event_node


func _make_card_at(board: Board, world_position: Vector2, rotation: float) -> CardEntity:
	var card := CardEntityScene.instantiate() as CardEntity
	var card_data := CardDataScript.new()
	card_data.card_type = CardDataScript.CardType.ROOT
	card.bind_instance(CardInstanceScript.new(card_data))
	root.add_child(card)
	card.global_position = board.to_global(world_position)
	card.rotation_degrees = rotation
	return card


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)


func _finish_tests() -> void:
	for child in root.get_children():
		child.free()
	await process_frame
	await process_frame
	quit(0 if _failure_count == 0 else 1)
