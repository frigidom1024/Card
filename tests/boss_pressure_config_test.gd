extends SceneTree

const BoardScene = preload("res://scenes/game/board.tscn")
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
const EventScene = preload("res://scenes/game/event.tscn")
const EventDataScript = preload("res://scripts/game/event/core/event_data.gd")
const BossPressureServiceScript = preload("res://scripts/game/exploration/boss_pressure_service.gd")

var _failure_count := 0


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	var tail := _make_card(board, Vector2(520, 364), -90.0)
	board.cards.append(tail)

	var boss := _make_boss_event(Vector2i(0, 0))
	_expect(board.attach_event(boss), "Boss event attaches before pursuit configuration is evaluated")
	var original_origin := boss.event_instance.origin

	var service := BossPressureServiceScript.new()
	service.configure(false, 1, 1)
	service.register_boss(boss)
	service.record_card_placed(board)
	service.record_card_placed(board)

	_expect(
		service.get_phase() == BossPressureServiceScript.Phase.ACTIVE,
		"disabled pursuit keeps the Boss in its normal active event state"
	)
	_expect(
		boss.event_instance.origin == original_origin,
		"disabled pursuit never changes the ordinary Boss event origin"
	)
	board.queue_free()
	quit(1 if _failure_count > 0 else 0)


func _make_card(board: Board, card_position: Vector2, card_rotation_degrees: float) -> CardEntity:
	var card := CardEntityScene.instantiate() as CardEntity
	board.add_child(card)
	card.position = card_position
	card.rotation_degrees = card_rotation_degrees
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