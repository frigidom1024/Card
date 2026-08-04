extends SceneTree

const BoardScene = preload("res://scenes/game/board.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const DragLayerScript = preload("res://scripts/game/drag_layer.gd")
const CardDataScript = preload("res://scripts/card/card_data.gd")
const CardInstanceScript = preload("res://scripts/card/card_instance.gd")
const EventDataScript = preload("res://scripts/game/event/core/event_data.gd")
const EventInstanceScript = preload("res://scripts/game/event/core/event_instance.gd")


class TrackingDragLayer extends DragLayer:
	var drag_end_call_count := 0

	func on_card_drag_end(card: CardEntity) -> void:
		drag_end_call_count += 1
		super.on_card_drag_end(card)


class RejectingHandArea extends HandArea:
	func add_card(_card: CardEntity, _animate: bool = true) -> bool:
		return false

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
	_test_drag_input_bypasses_event_controls_and_suspends_card_previews()
	_test_drag_lock_blocks_card_input_and_restores_an_active_drag()
	_test_lock_consumes_mouse_release_after_active_drag_cancel()
	_test_lock_restores_non_root_card_transform_and_occupancy()
	_test_restore_failure_returns_card_to_available_hand()
	_test_restore_failure_bypasses_full_hand_capacity_without_deletion()
	_test_restore_failure_keeps_card_in_recovery_container_after_hand_failure()
	_test_restore_failure_keeps_card_in_recovery_container_without_hand()
	call_deferred("_finish_tests")


func _test_event_placement_reserves_a_one_cell_gap() -> void:
	var board := _make_board(5, 1)
	_attach_event(board, "first", Vector2i(0, 0), Vector2i.ONE)
	var second := _new_event("second", Vector2i.ONE, Vector2i(1, 0))
	_expect(not board.can_attach_event(second.event_instance), "one empty cell is required")
	second.free()


func _test_event_placement_rejects_card_occupied_footprint() -> void:
	var board := _make_board(5, 2)
	var card := _make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)
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
	var card := _make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)
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
	board.add_card(_make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0))
	board.add_card(_make_card_at(board, Vector2(-80, 40), 90.0))
	_expect(trigger_count == 0, "resolved and rejected placements do not trigger")


func _test_failed_overlap_with_card_and_event_never_triggers() -> void:
	var board := _make_board(5, 2)
	_attach_event(board, "overlap", Vector2i(1, 0), Vector2i.ONE)
	var placed_card := _make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)
	_expect(board.add_card(placed_card), "setup card can cover the unresolved event")
	var trigger_count := 0
	board.event_triggered.connect(func(_instance): trigger_count += 1)
	var conflicting_candidate := _make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)
	_expect(
		not board.add_card(conflicting_candidate),
		"candidate overlapping an event and a placed card is rejected"
	)
	_expect(trigger_count == 0, "failed event overlap does not emit a trigger")


func _test_multiple_unresolved_event_overlap_never_triggers() -> void:
	var board := _make_board(5, 2)
	_inject_event_owner(board, _new_event("first", Vector2i.ONE, Vector2i(1, 0), board.cell_size))
	_inject_event_owner(board, _new_event("second", Vector2i.ONE, Vector2i(2, 0), board.cell_size))
	var trigger_count := 0
	board.event_triggered.connect(func(_instance): trigger_count += 1)
	_expect(
		board.add_card(_make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)),
		"exception fixture still has a legal card placement"
	)
	_expect(trigger_count == 0, "multiple unresolved event overlap never emits a trigger")


func _test_preview_never_triggers() -> void:
	var board := _make_board(5, 2)
	_attach_event(board, "preview-only", Vector2i(2, 0), Vector2i.ONE)
	var trigger_count := 0
	board.event_triggered.connect(func(_instance): trigger_count += 1)
	board.preview_card(_make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0))
	_expect(trigger_count == 0, "preview does not trigger events")


func _test_board_event_does_not_intercept_mouse_or_enable_selection() -> void:
	var board := _make_board(3, 2)
	var event_node := _attach_event(board, "non-interactive", Vector2i(1, 0), Vector2i.ONE)
	_expect(
		event_node.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"BoardEvent root ignores mouse input"
	)
	_expect(event_node.select_button.disabled, "BoardEvent select button remains disabled")
	_expect(
		event_node.select_button.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"BoardEvent disabled selection button passes mouse input through"
	)


func _test_drag_input_bypasses_event_controls_and_suspends_card_previews() -> void:
	var board := _make_board(5, 2)
	_attach_event(board, "pass-through", Vector2i(3, 0), Vector2i.ONE)
	var drag_layer := DragLayerScript.new() as DragLayer
	drag_layer.board = board
	root.add_child(drag_layer)
	var dragged_card := _make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)
	var hovered_card := _make_card_at(board, Vector2(-120.0, -120.0), 0.0, CardDataScript.CardType.NORMAL)
	dragged_card.drag_layer = drag_layer
	hovered_card.drag_layer = drag_layer
	_expect(board.add_card(dragged_card), "drag input setup card is placed on the Board")

	_card_left_click(dragged_card, true)
	_expect(drag_layer.has_method("is_drag_active"), "DragLayer exposes active-drag state")
	if drag_layer.has_method("is_drag_active"):
		_expect(drag_layer.is_drag_active(), "DragLayer reports an active card drag")

	hovered_card._on_mouse_entered()
	_expect(hovered_card.state == CardEntity.State.NORMAL, "other cards do not enter hover state during a drag")
	_expect(hovered_card.get_node_or_null("CardInfoOverlay") == null, "other cards do not open previews during a drag")

	var direction_before := dragged_card.card_instance.direction
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	drag_layer.call("_input", right_click)
	_expect(
		dragged_card.card_instance.direction == (direction_before + 1) % 4,
		"DragLayer rotates the dragged card even above an event control"
	)

func _test_drag_lock_blocks_card_input_and_restores_an_active_drag() -> void:
	var board := _make_board(5, 2)
	var drag_layer := DragLayerScript.new() as DragLayer
	drag_layer.board = board
	root.add_child(drag_layer)
	var card := _make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)
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


func _test_lock_consumes_mouse_release_after_active_drag_cancel() -> void:
	var board := _make_board(5, 2)
	var drag_layer := TrackingDragLayer.new()
	drag_layer.board = board
	root.add_child(drag_layer)
	var card := _make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)
	card.drag_layer = drag_layer
	_expect(board.add_card(card), "release-consumption setup card is placed")
	var original_parent := card.get_parent()
	var original_position := card.global_position
	var original_cells := board.get_card_cells(original_position, card.rotation_degrees)
	var clicked_cards: Array[CardEntity] = []
	card.clicked.connect(func(clicked_card): clicked_cards.append(clicked_card))

	_card_left_click(card, true)
	_expect(card._dragging, "real input starts the drag before lock")
	drag_layer.set_interaction_locked(true)
	var state_after_lock := card.state
	_expect(not card._dragging, "lock-driven cancel ends CardEntity drag state")
	_expect(_board_owns_cells(board, card, original_cells), "lock-driven cancel restores Board occupancy")

	_card_left_click(card, false)
	_expect(clicked_cards.is_empty(), "release after lock-driven cancel does not emit clicked")
	_expect(drag_layer.drag_end_call_count == 0, "release after lock-driven cancel does not run a second end")
	_expect(card.state == state_after_lock and not card._dragging, "release after cancel leaves CardEntity state stable")
	_expect(card.get_parent() == original_parent, "release after cancel preserves restored parent")
	_expect(card.global_position == original_position, "release after cancel preserves restored position")
	_expect(_board_owns_cells(board, card, original_cells), "release after cancel preserves Board occupancy")

	card._end_drag()
	_expect(
		drag_layer.drag_end_call_count == 0,
		"locked direct _end_drag does not invoke DragLayer completion"
	)
	_expect(card.state == state_after_lock, "locked direct _end_drag preserves state")
	_expect(card.get_parent() == original_parent, "locked direct _end_drag preserves parent")
	_expect(card.global_position == original_position, "locked direct _end_drag preserves position")
	_expect(_board_owns_cells(board, card, original_cells), "locked direct _end_drag preserves Board occupancy")


func _test_lock_restores_non_root_card_transform_and_occupancy() -> void:
	var board := _make_board(5, 2)
	var drag_layer := DragLayerScript.new() as DragLayer
	drag_layer.board = board
	root.add_child(drag_layer)
	var root_card := _make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)
	_expect(board.add_card(root_card), "non-root restore setup root card is placed")
	var card := _make_card_at(board, _horizontal_card_center(board, Vector2i(3, 0)), 90.0, CardDataScript.CardType.NORMAL)
	card.card_instance.direction = 1
	card.drag_layer = drag_layer
	_expect(board.add_card(card), "non-root restore setup card is placed")
	var original_parent := card.get_parent()
	var original_position := card.global_position
	var original_rotation := card.rotation_degrees
	var original_direction := card.card_instance.direction
	var original_cells := board.get_card_cells(original_position, original_rotation)

	_card_left_click(card, true)
	_expect(card._dragging and card.get_parent() == drag_layer, "non-root card enters real drag chain")
	card.rotation_degrees = 180.0
	card.card_instance.direction = 2
	drag_layer.set_interaction_locked(true)
	_expect(not card._dragging, "locking cancels dragged non-root card")
	_expect(card.get_parent() == original_parent, "locking restores non-root parent")
	_expect(card.global_position == original_position, "locking restores non-root position")
	_expect(card.rotation_degrees == original_rotation, "locking restores non-root rotation before Board placement")
	_expect(card.card_instance.direction == original_direction, "locking restores non-root direction before Board placement")
	_expect(_board_owns_cells(board, card, original_cells), "locking restores non-root Board membership and footprint")


func _test_restore_failure_returns_card_to_available_hand() -> void:
	var board := _make_board(5, 2)
	var hand := _make_hand(2)
	var drag_layer := _make_drag_layer(board, hand)
	var card := _make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)
	card.drag_layer = drag_layer
	var original_instance := card.card_instance
	_expect(board.add_card(card), "available-hand failure setup card is placed")
	_force_restore_failure_with_origin_blocker(board, card)
	drag_layer.set_interaction_locked(true)
	_expect_restore_failure_keeps_card_off_board(board, card, original_instance, hand, "available HandArea")
	_expect(card in hand.cards, "available HandArea records recovered card")


func _test_restore_failure_bypasses_full_hand_capacity_without_deletion() -> void:
	var board := _make_board(5, 2)
	var hand := _make_hand(1)
	var drag_layer := _make_drag_layer(board, hand)
	var filler := _make_card_at(board, Vector2(-80, 40), 90.0)
	_expect(hand.add_card(filler, false), "full-hand failure setup fills HandArea")
	_expect(hand.is_full(), "full-hand failure setup reaches normal capacity")
	var card := _make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)
	card.drag_layer = drag_layer
	var original_instance := card.card_instance
	_expect(board.add_card(card), "full-hand failure setup card is placed")
	_force_restore_failure_with_origin_blocker(board, card)
	drag_layer.set_interaction_locked(true)
	_expect_restore_failure_keeps_card_off_board(board, card, original_instance, hand, "full HandArea")
	_expect(card in hand.cards, "full HandArea bypasses normal capacity for cancellation recovery")
	_expect(hand.cards.size() == 2 and hand.max_hand_size == 1, "recovery preserves the configured hand capacity after forced return")


func _test_restore_failure_keeps_card_in_recovery_container_after_hand_failure() -> void:
	var board := _make_board(5, 2)
	var hand := RejectingHandArea.new()
	root.add_child(hand)
	var drag_layer := _make_drag_layer(board, hand)
	var card := _make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)
	card.drag_layer = drag_layer
	var original_instance := card.card_instance
	_expect(board.add_card(card), "rejecting-hand failure setup card is placed")
	_force_restore_failure_with_origin_blocker(board, card)
	drag_layer.set_interaction_locked(true)
	var recovery_container := drag_layer.get_node_or_null("InteractionLockRecovery")
	_expect(recovery_container != null, "hand add failure creates a named recovery container")
	_expect_restore_failure_keeps_card_off_board(board, card, original_instance, recovery_container, "hand-failure recovery container")
	_expect(not card.is_queued_for_deletion(), "hand add failure never queues the player card for deletion")


func _test_restore_failure_keeps_card_in_recovery_container_without_hand() -> void:
	var board := _make_board(5, 2)
	var drag_layer := _make_drag_layer(board)
	var card := _make_card_at(board, _horizontal_card_center(board, Vector2i(1, 0)), 90.0)
	card.drag_layer = drag_layer
	var original_instance := card.card_instance
	_expect(board.add_card(card), "no-hand failure setup card is placed")
	_force_restore_failure_with_origin_blocker(board, card)
	drag_layer.set_interaction_locked(true)
	var recovery_container := drag_layer.get_node_or_null("InteractionLockRecovery")
	_expect(recovery_container != null, "no-hand restore failure creates a named recovery container")
	_expect_restore_failure_keeps_card_off_board(board, card, original_instance, recovery_container, "recovery container")
	_expect(not card.is_queued_for_deletion(), "no-hand restore failure never queues the player card for deletion")


func _make_drag_layer(board: Board, hand: HandArea = null) -> DragLayer:
	var drag_layer := DragLayerScript.new() as DragLayer
	drag_layer.board = board
	drag_layer.hand_area = hand
	root.add_child(drag_layer)
	return drag_layer


func _make_hand(max_hand_size: int) -> HandArea:
	var hand := HandArea.new()
	hand.max_hand_size = max_hand_size
	root.add_child(hand)
	return hand


func _force_restore_failure_with_origin_blocker(board: Board, card: CardEntity) -> void:
	var origin_position := card.global_position
	var origin_rotation := card.rotation_degrees
	_card_left_click(card, true)
	_expect(card._dragging, "restore-failure setup enters real drag chain")
	var blocker := _make_card_at(board, board.to_local(origin_position), origin_rotation)
	_expect(board.add_card(blocker), "restore-failure setup places a blocker at the original footprint")


func _expect_restore_failure_keeps_card_off_board(
	board: Board,
	card: CardEntity,
	original_instance: CardInstance,
	expected_parent: Node,
	label: String
) -> void:
	_expect(is_instance_valid(card), label + " retains the CardEntity node")
	_expect(card.card_instance == original_instance, label + " retains the CardInstance")
	_expect(not card.is_queued_for_deletion(), label + " does not queue the player card for deletion")
	_expect(card.get_parent() == expected_parent, label + " is the exact fallback parent")
	_expect(card.get_parent() != board, label + " never reparents the failed card directly to Board")
	_expect(card not in board.cards, label + " leaves no Board cards membership")
	_expect(not _board_has_owner(board, card), label + " leaves no Board grid ownership")


func _board_has_owner(board: Board, card: CardEntity) -> bool:
	for owner in board._grid_owner.values():
		if owner == card:
			return true
	return false


func _make_board(board_width: int, board_height: int) -> Board:
	var board := BoardScene.instantiate() as Board
	board.width = board_width
	board.height = board_height
	root.add_child(board)
	return board


func _new_event(
	event_id: String,
	event_size: Vector2i,
	origin: Vector2i,
	cell_size: int = LayoutConfig.CELL_SIZE
) -> BoardEvent:
	var template := EventDataScript.new()
	template.event_id = event_id
	template.size = event_size
	var instance := EventInstanceScript.new()
	instance.template = template
	instance.origin = origin
	var event_node := EventScene.instantiate() as BoardEvent
	event_node.setup(instance, cell_size)
	return event_node


func _attach_event(board: Board, event_id: String, origin: Vector2i, event_size: Vector2i) -> BoardEvent:
	var event_node := _new_event(event_id, event_size, origin, board.cell_size)
	_expect(board.attach_event(event_node), "event attaches to board")
	return event_node


func _inject_event_owner(board: Board, event_node: BoardEvent) -> void:
	board.add_child(event_node)
	board.events.append(event_node)
	for cell in board.get_event_cells(event_node.event_instance.origin, event_node.event_instance.get_size()):
		board._event_grid_owner[cell] = event_node


func _horizontal_card_center(board: Board, left_cell: Vector2i) -> Vector2:
	var right_cell := left_cell + Vector2i.RIGHT
	return board.to_local(
		(board.grid_to_world_center(left_cell) + board.grid_to_world_center(right_cell)) / 2.0
	)


func _make_card_at(
	board: Board,
	world_position: Vector2,
	rotation: float,
	card_type = CardDataScript.CardType.ROOT
) -> CardEntity:
	var card := CardEntityScene.instantiate() as CardEntity
	var card_data := CardDataScript.new()
	card_data.card_type = card_type
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
