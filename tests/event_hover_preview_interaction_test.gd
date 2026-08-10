extends SceneTree

const BoardScene = preload("res://scenes/game/board.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const EventDataScript = preload("res://scripts/game/event/core/event_data.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _test_board_event_emits_hover_lifecycle_without_triggering_event()
	await _test_resolved_board_event_does_not_emit_hover_request()
	await _test_board_notifies_dynamic_event_attach_and_remove()
	quit(1 if _failure_count > 0 else 0)


func _test_board_event_emits_hover_lifecycle_without_triggering_event() -> void:
	var fixture := await _create_board_and_event(EventData.EventType.MONSTER, "hover_echo")
	var board: Board = fixture.board
	var event_node: BoardEvent = fixture.event_node
	var instance: EventInstance = event_node.event_instance
	var hover_events: Array[String] = []
	var triggered_count := 0
	event_node.hover_started.connect(func(_node: BoardEvent) -> void:
		hover_events.append("started")
	)
	event_node.hover_ended.connect(func(_node: BoardEvent) -> void:
		hover_events.append("ended")
	)
	board.event_triggered.connect(func(_event: EventInstance) -> void:
		triggered_count += 1
	)

	event_node.mouse_entered.emit()
	event_node.mouse_exited.emit()
	_expect(hover_events == ["started", "ended"], "unresolved event emits hover start and end")
	_expect(not instance.is_revealed and not instance.is_resolved, "hover does not reveal or resolve event")
	_expect(triggered_count == 0, "hover does not trigger event interaction")
	_expect(event_node.mouse_filter != Control.MOUSE_FILTER_IGNORE, "event root receives hover input")
	for child in event_node.get_children():
		if child is Control:
			_expect(child.mouse_filter == Control.MOUSE_FILTER_IGNORE, "event visual child ignores pointer input")
	await _free_fixture(fixture)


func _test_resolved_board_event_does_not_emit_hover_request() -> void:
	var fixture := await _create_board_and_event(EventData.EventType.MONSTER, "resolved_echo")
	var event_node: BoardEvent = fixture.event_node
	var hover_count := 0
	event_node.hover_started.connect(func(_node: BoardEvent) -> void:
		hover_count += 1
	)
	event_node.event_instance.resolve()
	event_node.refresh_display()
	event_node.mouse_entered.emit()
	_expect(hover_count == 0, "resolved event does not emit hover preview request")
	await _free_fixture(fixture)


func _test_board_notifies_dynamic_event_attach_and_remove() -> void:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	var lifecycle: Array[String] = []
	board.event_attached.connect(func(_event_node: BoardEvent) -> void:
		lifecycle.append("attached")
	)
	board.event_removed.connect(func(_event_node: BoardEvent) -> void:
		lifecycle.append("removed")
	)
	var event_node := _make_event(EventData.EventType.BOSS, "moving_boss")
	_expect(board.attach_event(event_node), "board attaches dynamic event")
	_expect(lifecycle == ["attached"], "board notifies after event attach")
	_expect(board.remove_event(event_node), "board removes dynamic event")
	_expect(lifecycle == ["attached", "removed"], "board notifies after event removal")
	board.queue_free()
	await process_frame


func _create_board_and_event(event_type: int, event_id: String) -> Dictionary:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	var event_node := _make_event(event_type, event_id)
	_expect(board.attach_event(event_node), "fixture attaches event")
	await process_frame
	return {"board": board, "event_node": event_node}


func _make_event(event_type: int, event_id: String) -> BoardEvent:
	var data := EventDataScript.new()
	data.event_id = event_id
	data.event_type = event_type
	var instance := data.create_instance()
	instance.origin = Vector2i(1, 1)
	var event_node := EventScene.instantiate() as BoardEvent
	event_node.setup(instance, 80)
	return event_node


func _free_fixture(fixture: Dictionary) -> void:
	var board: Board = fixture.board
	if is_instance_valid(board):
		board.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error(message)
