extends SceneTree

const BoardScene := preload("res://scenes/game/board.tscn")
const CardEntityScene := preload("res://scenes/card_view/card_entity.tscn")
const EventScene := preload("res://scenes/game/event.tscn")
const EventDataScript := preload("res://scripts/game/event/core/event_data.gd")
const BoardPlacementResultScript := preload("res://scripts/game/board_placement_result.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_chain_placement_publishes_only_spatial_transaction()
	quit(1 if _failure_count > 0 else 0)


func _test_chain_placement_publishes_only_spatial_transaction() -> void:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	var root_card := _make_root_card(board, Vector2(280, 200), 0.0)
	var event_cell := board.get_card_cells(root_card.global_position, root_card.rotation_degrees)[0]
	var echo := _make_monster_event(event_cell)
	_expect(board.attach_event(echo), "an unresolved echo can occupy the root card cell")

	var committed_results: Array[BoardPlacementResult] = []
	board.placement_committed.connect(func(result: BoardPlacementResult) -> void:
		committed_results.append(result)
	)
	_expect(
		not board.has_signal("event_interaction_requested"),
		"Board only publishes the placement result; exploration requests interaction"
	)

	_expect(board.add_card(root_card), "root card commits over an unresolved echo")
	_expect(committed_results.size() == 1, "placement publishes exactly one spatial result")
	if committed_results.size() == 1:
		var committed_result := committed_results[0]
		_expect(committed_result.source_card == root_card, "result keeps the source card")
		_expect(committed_result.overlapped_event == echo.event_instance, "result exposes the overlapped event")
		_expect(committed_result.newly_occupied_cells == board.get_card_cells(root_card.global_position, root_card.rotation_degrees), "result records newly occupied cells")
	board.queue_free()

func _make_root_card(board: Board, position: Vector2, rotation_degrees: float) -> CardEntity:
	var card := CardEntityScene.instantiate() as CardEntity
	board.add_child(card)
	card.position = position
	card.rotation_degrees = rotation_degrees
	var data := CardData.new()
	data.card_type = CardData.CardType.ROOT
	card.card_instance = CardInstance.new(data)
	return card


func _make_monster_event(origin: Vector2i) -> BoardEvent:
	var data := EventDataScript.new()
	data.event_id = "test_echo"
	data.event_type = EventDataScript.EventType.MONSTER
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
