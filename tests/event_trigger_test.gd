extends SceneTree

const BoardScene = preload("res://scenes/game/board.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const DragLayerScript = preload("res://scripts/game/drag_layer.gd")
const CardDataScript = preload("res://scripts/card/card_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const EventDataScript = preload("res://scripts/game/event/event_data.gd")
const EventInstanceScript = preload("res://scripts/game/event/event_zone.gd")

var _failure_count := 0


func _init() -> void:
	_test_event_placement_reserves_a_one_cell_gap()
	_test_event_placement_rejects_card_occupied_footprint()
	_test_successful_card_placement_triggers_exactly_one_event()
	_test_resolved_or_failed_placement_never_triggers()
	_test_failed_overlap_with_card_and_event_never_triggers()
	_test_multiple_unresolved_event_overlap_never_triggers()
	_test_preview_never_triggers()
	call_deferred("_run_scene_interaction_tests")


func _run_scene_interaction_tests() -> void:
	await process_frame
	_test_board_event_does_not_intercept_mouse_or_enable_selection()
	_test_drag_lock_blocks_card_input_and_restores_an_active_drag()
	call_deferred("_finish_tests")


func _test_event_placement_reserves_a_one_cell_gap() -> void:
	var board := _make_board(5, 1)
	_attach_event(board, "first", Vector2i(0, 0), Vector2i.ONE)
	var second := _new_event("second", Vector2i.ONE, Vector2i(1, 0))
	_expect(not board.can_attach_event(second.event_instance), "one empty cell is required")
	second.free()


func _test_event_placement_rejects_card_occupied_footprint() -> void:
	var board := _make_board(5, 2)
	var card := _make_card_at(board, Vector2(120, 40), 90.0)
	_expect(board.add_card(card), "setup card is legally placed")
	var candidate := _new_event("blocked-by-card", Vector2i.ONE, Vector2i(1, 0))
	_expect(
		not board.can_attach_event(candidate.event_instance),
		"event footprint occupied by a card is rejected"
	)
	candidate.free()


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


func _test_failed_overlap_with_card_and_event_never_triggers() -> void:
	var board := _make_board(5, 2)
	_attach_event(board, "overlap", Vector2i(1, 0), Vector2i.ONE)
	var placed_card := _make_card_at(board, Vector2(120, 40), 90.0)
	_expect(board.add_card(placed_card), "setup card can cover the unresolved event")
	var trigger_count := 0
	board.event_triggered.connect(func(_instance): trigger_count += 1)
	var conflicting_candidate := _make_card_at(board, Vector2(120, 40), 90.0)
	_expect(
		not board.add_card(conflicting_candidate),
		"candidate overlapping an event and a placed card is rejected"
	)
	_expect(trigger_count == 0, "failed event overlap does not emit a trigger")


func _test_multiple_unresolved_event_overlap_never_triggers() -> void:
	var board := _make_board(5, 2)
	_inject_event_owner(board, _new_event("first", Vector2i.ONE, Vector2i(1, 0)))
	_inject_event_owner(board, _new_event("second", Vector2i.ONE, Vector2i(2, 0)))
	var trigger_count := 0
	board.event_triggered.connect(func(_instance): trigger_count += 1)
	_expect(
		board.add_card(_make_card_at(board, Vector2(120, 40), 90.0)),
		"exception fixture still has a legal card placement"
	)
	_expect(trigger_count == 0, "multiple unresolved event overlap never emits a trigger")


func _test_preview_never_triggers() -> void:
	var board := _make_board(5, 2)
	_attach_event(board, "preview-only", Vector2i(2, 0), Vector2i.ONE)
	var trigger_count := 0
	board.event_triggered.connect(func(_instance): trigger_count += 1)
	board.preview_card(_make_card_at(board, Vector2(120, 40), 90.0))
	_expect(trigger_count == 0, "preview does not trigger events")


func _test_board_event_does_not_intercept_mouse_or_enable_selection() -> void:
	var board := _make_board(3, 2)
	var event_node := _attach_event(board, "non-interactive", Vector2i(1, 0), Vector2i.ONE)
	_expect(
		event_node.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"BoardEvent root ignores mouse input"
	)
	_expect(event_node.select_button.disabled, "BoardEvent select button remains disabled")


func _test_drag_lock_blocks_card_input_and_restores_an_active_drag() -> void:
	var board := _make_board(5, 2)
	var drag_layer := DragLayerScript.new() as DragLayer
	drag_layer.board = board
	root.add_child(drag_layer)
	var card := _make_card_at(board, Vector2(120, 40), 90.0)
	card.drag_layer = drag_layer
	_expect(board.add_card(card), "drag-lock setup card is placed on the Board")
	var original_parent := card.get_parent()
	var original_position := card.global_position
	var original_cells := board.get_card_cells(card.global_position, card.rotation_degrees)

	drag_layer.set_interaction_locked(true)
	var has_lock_read_api := drag_layer.has_method("is_interaction_locked")
	_expect(has_lock_read_api, "DragLayer exposes lock-read API")
	if has_lock_read_api:
		_expect(drag_layer.is_interaction_locked(), "DragLayer reports the active interaction lock")
	_card_left_click(card, true)
	_expect(card.get_parent() == original_parent, "locked drag start preserves the card parent")
	_expect(card.global_position == original_position, "locked drag start preserves the card position")
	_expect(not card._dragging, "locked drag start does not set CardEntity dragging state")
	_expect(_board_owns_cells(board, card, original_cells), "locked drag start preserves Board occupancy")
	_card_left_click(card, false)
	_expect(card.get_parent() == original_parent, "locked drag end preserves the card parent")
	_expect(card.global_position == original_position, "locked drag end preserves the card position")
	_expect(not card._dragging, "locked drag end does not change CardEntity dragging state")
	_expect(_board_owns_cells(board, card, original_cells), "locked drag end preserves Board occupancy")

	drag_layer.set_interaction_locked(false)
	_card_left_click(card, true)
	_expect(card._dragging and card.get_parent() == drag_layer, "unlocked input starts the real drag chain")
	drag_layer.set_interaction_locked(true)
	_expect(not card._dragging, "locking during a drag cancels CardEntity dragging state")
	_expect(card.get_parent() == original_parent, "locking during a drag restores the original parent")
	_expect(card.global_position == original_position, "locking during a drag restores the original position")
	_expect(_board_owns_cells(board, card, original_cells), "locking during a drag restores Board occupancy")
	_card_left_click(card, false)
	_expect(card.get_parent() == original_parent, "locked post-cancel drag end preserves the restored parent")
	_expect(card.global_position == original_position, "locked post-cancel drag end preserves the restored position")
	_expect(not card._dragging, "locked post-cancel drag end preserves non-dragging state")
	_expect(_board_owns_cells(board, card, original_cells), "locked post-cancel drag end preserves Board occupancy")


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


func _inject_event_owner(board: Board, event_node: BoardEvent) -> void:
	board.add_child(event_node)
	board.events.append(event_node)
	for cell in board.get_event_cells(event_node.event_instance.origin, event_node.event_instance.get_size()):
		board._event_grid_owner[cell] = event_node


func _make_card_at(board: Board, world_position: Vector2, rotation: float) -> CardEntity:
	var card := CardEntityScene.instantiate() as CardEntity
	var card_data := CardDataScript.new()
	card_data.card_type = CardDataScript.CardType.ROOT
	card.bind_instance(CardInstanceScript.new(card_data))
	root.add_child(card)
	card.global_position = board.to_global(world_position)
	card.rotation_degrees = rotation
	return card


func _card_left_click(card: CardEntity, pressed: bool) -> void:
	var input := InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.pressed = pressed
	card._on_input_event(root, input, 0)


func _board_owns_cells(board: Board, card: CardEntity, cells: Array[Vector2i]) -> bool:
	if card not in board.cards:
		return false
	for cell in cells:
		if board._grid_owner.get(cell) != card:
			return false
	return true


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
