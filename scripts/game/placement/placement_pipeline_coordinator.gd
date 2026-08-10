class_name PlacementPipelineCoordinator
extends RefCounted

## Owns the sole Board placement subscription, resolves card rules before exploration,
## and routes the committed event contact directly to RunFlowCoordinator.
signal event_interaction_requested(instance: EventInstance)
signal placement_resolved(result: BoardPlacementResult, card_rules_applied: int)

var _board: Board
var _card_chain: CardChainCoordinator
var _exploration: ExplorationCoordinator
var _placement_guard: Callable


func configure(
	board: Board, card_chain: CardChainCoordinator, exploration: ExplorationCoordinator
) -> bool:
	if board == null or card_chain == null or exploration == null:
		return false
	if _board != null and _board.placement_committed.is_connected(_on_placement_committed):
		_board.placement_committed.disconnect(_on_placement_committed)
	_board = board
	_card_chain = card_chain
	_exploration = exploration
	_placement_guard = Callable()
	return true


func set_placement_guard(guard: Callable) -> bool:
	if not guard.is_valid():
		return false
	_placement_guard = guard
	return true


func connect_board() -> bool:
	if _board == null:
		return false
	if not _board.placement_committed.is_connected(_on_placement_committed):
		_board.placement_committed.connect(_on_placement_committed)
	return true


func resolve_placement(result: BoardPlacementResult) -> void:
	if result == null or _card_chain == null or _exploration == null:
		return
	if _placement_guard.is_valid() and not _placement_guard.call():
		return
	var card_rules_applied := _card_chain.resolve_placement(result)
	_exploration.resolve_placement(result)
	_emit_event_interaction_request(result)
	placement_resolved.emit(result, card_rules_applied)


func _on_placement_committed(result: BoardPlacementResult) -> void:
	resolve_placement(result)


func _emit_event_interaction_request(result: BoardPlacementResult) -> void:
	if result == null or result.overlapped_event == null:
		return
	if result.overlapped_event.is_resolved:
		return
	event_interaction_requested.emit(result.overlapped_event)
