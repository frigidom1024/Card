extends SceneTree

const BoardScene := preload("res://scenes/game/board.tscn")
const EventDataScript := preload("res://scripts/game/event/core/event_data.gd")
const PlacementPipelineCoordinatorScript := preload(
	"res://scripts/game/placement/placement_pipeline_coordinator.gd"
)

class RecordingCardChain extends CardChainCoordinator:
	var order: Array[String]
	var applied_count: int

	func _init(initial_order: Array[String], initial_applied_count: int) -> void:
		order = initial_order
		applied_count = initial_applied_count

	func resolve_placement(_result: BoardPlacementResult) -> int:
		order.append("card_chain")
		return applied_count


class RecordingExploration extends ExplorationCoordinator:
	var order: Array[String]
	var contact_to_emit: EventInstance

	func _init(initial_order: Array[String], initial_contact: EventInstance = null) -> void:
		order = initial_order
		contact_to_emit = initial_contact

	func resolve_placement(_result: BoardPlacementResult) -> void:
		order.append("exploration")
		if contact_to_emit != null:
			event_interaction_requested.emit(contact_to_emit)


var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_card_chain_resolves_before_exploration_after_board_commit()
	_test_pipeline_forwards_one_exploration_contact()
	quit(1 if _failure_count > 0 else 0)


func _test_card_chain_resolves_before_exploration_after_board_commit() -> void:
	var board := _make_board()
	var order: Array[String] = []
	var pipeline := PlacementPipelineCoordinatorScript.new()
	var card_chain := RecordingCardChain.new(order, 3)
	var exploration := RecordingExploration.new(order)
	var applied_counts: Array[int] = []
	pipeline.placement_resolved.connect(
		func(_result: BoardPlacementResult, applied_count: int) -> void: applied_counts.append(applied_count)
	)

	_expect(pipeline.configure(board, card_chain, exploration), "pipeline accepts configured placement coordinators")
	_expect(pipeline.connect_board(), "pipeline subscribes to Board placement commits")
	board.placement_committed.emit(_make_chain_extended_result())

	_expect(order == ["card_chain", "exploration"], "card-chain rules resolve before exploration")
	_expect(applied_counts == [3], "pipeline reports the card rules applied for the placement")
	board.queue_free()


func _test_pipeline_forwards_one_exploration_contact() -> void:
	var board := _make_board()
	var order: Array[String] = []
	var contact := EventDataScript.new().create_instance()
	var pipeline := PlacementPipelineCoordinatorScript.new()
	var received: Array[EventInstance] = []
	_expect(
		pipeline.configure(
			board,
			RecordingCardChain.new(order, 0),
			RecordingExploration.new(order, contact)
		),
		"pipeline configures contact forwarding"
	)
	pipeline.event_interaction_requested.connect(
		func(instance: EventInstance) -> void: received.append(instance)
	)

	pipeline.resolve_placement(_make_chain_extended_result())

	_expect(received == [contact], "pipeline forwards each exploration contact exactly once")
	board.queue_free()


func _make_board() -> Board:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	return board


func _make_chain_extended_result() -> BoardPlacementResult:
	return BoardPlacementResult.new(
		BoardPlacementResult.Kind.CHAIN_EXTENDED, null, null, [], []
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)